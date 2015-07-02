-module(turtle_conn).
-behaviour(gen_server).
-include_lib("amqp_client/include/amqp_client.hrl").

%% Lifetime
-export([
	start_link/2
]).

%% API
-export([
	open_channel/1
]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(DEFAULT_RETRY_TIME, 15*1000).

-record(state, {
	network_params :: #amqp_params_network{},
	connection = undefined :: undefined | pid(),
	retry_time = ?DEFAULT_RETRY_TIME :: pos_integer()
}).

%% LIFETIME MAINTENANCE
%% ----------------------------------------------------------
start_link(Name, Configuration) ->
    gen_server:start_link({via, gproc, {n,l, {turtle, connection, Name}}}, ?MODULE, [Name, Configuration], []).
	
open_channel(Name) ->
    call(Name, open_channel).
    
call(Loc, Msg) ->
    Pid = gproc:where({n,l,{turtle, connection, Loc}}),
    gen_server:call(Pid, Msg, 20*1000).

%% CALLBACKS
%% -------------------------------------------------------------------

%% @private
init([_Name, Configuration]) ->
    self() ! connect,
    {ok, #state {
    	network_params = Configuration
    }}.

%% @private
handle_call(_Msg, _From, #state { connection = undefined } = State) ->
    {reply, {error, no_amqp_connection}, State};
handle_call(open_channel, _From, #state { connection = Conn } = State) ->
    ChanRes = amqp_connection:open_channel(Conn),
    {reply, ChanRes, State};
handle_call(Call, From, State) ->
    lager:warning("Unknown call from ~p: ~p", [From, Call]),
    {reply, {error, unknown_call}, State}.

%% @private
handle_cast(Cast, State) ->
    lager:warning("Unknown cast: ~p", [Cast]),
    {noreply, State}.

%% @private
handle_info(connect, #state { network_params = NP, retry_time = Retry } = State) ->
    case connect(State) of
        {ok, ConnectedState} -> {noreply, ConnectedState};
        {error, unknown_host} ->
            lager:error("Unknown host while connecting to RabbitMQ: ~p", [NP]),
            {stop, {error, unknown_host}, State};
        {error, timeout} ->
            lager:warning("Timeout while connecting to RabbitMQ: ~p", [NP]),
            erlang:send_after(Retry, self(), connect),
            {noreply, State}
    end;
handle_info(_, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_, State, _) ->
    {ok, State}.

%%
%% INTERNAL FUNCTIONS
%%
connect(#state { network_params = NP } = State) ->
    case amqp_connection:start(NP) of
       {ok, Conn} -> {ok, State#state { connection = Conn }};
       {error, Reason} -> {error, Reason}
    end.
