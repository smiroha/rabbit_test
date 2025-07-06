-module(rt_publisher).

-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbit_test.hrl").

-export([start_link/2]).
-export([init/1, handle_info/2, handle_call/3, handle_cast/2, terminate/2]).


start_link(Name, Tid) ->
	gen_server:start_link({local, Name}, ?MODULE, [Name, Tid], []).

init([Name, Tid]) ->
	_ = process_flag(trap_exit, true),
	_ = erlang:send_after(50, self(), connect),
	{ok, #{name => Name, tid => Tid}}.


handle_call(_, _, State) -> {reply, ok, State}.

handle_cast(_, State) -> {noreply, State}.

handle_info(publish, State = #{name := Name, tid := Tid, channel := Chan}) ->
	Seq = ets:update_counter(Tid, Name, {2, 1}, {Name, 0}),
	Method = #'basic.publish'{exchange = ?EXCHANGE},
	Content = #amqp_msg{
		props = #'P_basic'{delivery_mode = 2},
		payload = term_to_binary(#{seq => Seq, from => Name})
	},
	ok = amqp_channel:cast(Chan, Method, Content),
	{noreply, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_conn_mref := MRef}) -> {stop, {died_conn, Reason}, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_chan_mref := MRef}) -> {stop, {died_chan, Reason}, State};
handle_info(connect, OldState = #{name := Name, tid := Tid}) ->
	{ok, State} = connect(OldState),
	logger:info("publisher:~p (re)connected seq:~p", [Name, ets:lookup(Tid, Name)]),
	{ok, _TRef} = timer:send_interval(10, publish),
	{noreply, State};
handle_info(Msg, State = #{name := Name}) ->
	logger:warning("publisher:~p handle unexpected msg:~p", [Name, Msg]),
	{noreply, State}.

terminate(Reason, #{name := Name}) ->
	logger:warning("publisher:~p terminated by reason:~p", [Name, Reason]),
	timer:sleep(3000),
	ok.

%% @private
connect(State = #{name := Name}) ->
	ConnProps = [{<<"connection_name">>, longstr, atom_to_binary(Name)}],
	AmqpParams = #amqp_params_network{client_properties = ConnProps},
	{ok, AMQPConn} = amqp_connection:start(AmqpParams),
	{ok, AMQPChan} = amqp_connection:open_channel(AMQPConn),
	AMQPConnMRef = erlang:monitor(process, AMQPConn),
	AMQPChanMRef = erlang:monitor(process, AMQPChan),
	Declare = #'exchange.declare'{exchange = ?EXCHANGE, type = <<"topic">>, durable = true},
	#'exchange.declare_ok'{} = amqp_channel:call(AMQPChan, Declare),
	{ok, State#{channel => AMQPChan, amqp_conn_mref => AMQPConnMRef, amqp_chan_mref => AMQPChanMRef}}.