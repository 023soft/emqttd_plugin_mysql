%%%-----------------------------------------------------------------------------
%%% Copyright (c) 2012-2015 eMQTT.IO, All Rights Reserved.
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in all
%%% copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%%% SOFTWARE.
%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd authentication by mysql 'user' table.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_auth_mysql).

-author("Feng Lee <feng@emqtt.io>").

-include("emqttd.hrl").

-behaviour(emqttd_auth_mod).

-export([init/1, check/3, description/0]).

-define(NOT_LOADED, not_loaded(?LINE)).

-record(state, {user_table, name_field, pass_field, user_pk_field, pass_hash, token_table, token_field, token_user_pk_field}).

init(Opts) ->
  Mapper = proplists:get_value(field_mapper, Opts),
  {ok, #state{user_table = proplists:get_value(user_table, Opts, auth_user),
    token_table = proplists:get_value(token_table, Opts, authtoken_token),
    name_field = proplists:get_value(username, Mapper),
    user_pk_field = proplists:get_value(user_pk, Mapper),
    pass_field = proplists:get_value(password, Mapper),
    token_user_pk_field = proplists:get_value(key, Mapper),
    token_field = proplists:get_value(user_id, Mapper),
    pass_hash = proplists:get_value(Opts, password_hash)}}.

check(#mqtt_client{username = undefined}, _Password, _State) ->
  {error, "Username undefined"};
check(_Client, undefined, _State) ->
  {error, "Password undefined"};
check(#mqtt_client{username = Username}, Password,
    #state{user_table = UserTab, pass_hash = Type,
      name_field = NameField, pass_field = PassField, token_table = TokenTab, user_pk_field = UserPkField, token_user_pk_field = TokenUserField, token_field = TokenField}) ->
  Where = {'and', {NameField, Username}, {PassField, hash(Type, Password)}},
  Where1 = {'and', {NameField, Username}, {TokenField, Password}},
  Where2 = {'and', Where1, {UserTab ++ "." ++ UserPkField, TokenTab ++ "." ++ TokenUserField}},
  if Type =:= pbkdf2 ->
    case emysql:select(UserTab, [PassField], {NameField, Username}) of
      {ok, []} -> {error, "User not exist"};
      {ok, Records} ->
        if length(Records) =:= 1 ->
          case pbkdf2_check(Password, lists:nth(Records, 1)) of
            true ->
              {ok, []};
            false ->
              {error, "UserName or Password is invalid"};
            ErrorInfo ->
              {error, ErrorInfo}
          end;
          true ->
            {error, "UserName is ambiguous"}
        end
    end;
    Type =:= authtoken ->
      case emysql:sqlquery(UserTab ++ "," ++ TokenTab, Where2) of
        {ok, []} -> {error, "Username or Password "};
        {ok, _Records} -> ok
      end;
    true ->
      case emysql:select(UserTab, Where) of
        {ok, []} -> {error, "Username or Password "};
        {ok, _Record} -> ok
      end
  end.

description() -> "Authentication by MySQL".

hash(plain, Password) ->
  Password;

hash(md5, Password) ->
  hexstring(crypto:hash(md5, Password));

hash(sha, Password) ->
  hexstring(crypto:hash(sha, Password)).

hexstring(<<X:128/big-unsigned-integer>>) ->
  lists:flatten(io_lib:format("~32.16.0b", [X]));

hexstring(<<X:160/big-unsigned-integer>>) ->
  lists:flatten(io_lib:format("~40.16.0b", [X])).

not_loaded(Line) ->
  erlang:nif_error({not_loaded, [{module, ?MODULE}, {line, Line}]}).

pbkdf2_check(Password, Pbkstr) ->
  case nif_pbkdf2_check(Password, Pbkstr) of
    {error, _} = Error ->
      throw(Error);
    IOData ->
      IOData
  end.

nif_pbkdf2_check(Password, Pbkstr) ->
  ?NOT_LOADED.

