-module(rt_publisher).

-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbit_test.hrl").

-export([start_link/1]).
-export([init/1, handle_info/2, handle_call/3, handle_cast/2, terminate/2]).


start_link(Tid) ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [Tid], []).

init([Tid]) ->
	_ = process_flag(trap_exit, true),
	_ = erlang:send_after(50, self(), connect),
	{ok, #{tid => Tid}}.


handle_call(_, _, State) -> {reply, ok, State}.

handle_cast(_, State) -> {noreply, State}.

handle_info(publish, State = #{tid := Tid, channel := Chan}) ->
	Seq = ets:update_counter(Tid, seq, {2, 1}, {seq, 0}),
	Method = #'basic.publish'{exchange = ?EXCHANGE},
	Content = #amqp_msg{
		props = #'P_basic'{delivery_mode = 2},
		payload = term_to_binary(#{seq => Seq, form => node()})
	},
	ok = amqp_channel:cast(Chan, Method, Content),
	{noreply, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_conn_mref := MRef}) -> {stop, {died_conn, Reason}, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_chan_mref := MRef}) -> {stop, {died_chan, Reason}, State};
handle_info(connect, OldState = #{tid := Tid}) ->
	{ok, State} = connect(OldState),
	logger:info("publisher (re)connected seq:~p", [ets:lookup(Tid, seq)]),
	{ok, _TRef} = timer:send_interval(10, publish), %% 100 rps
	{noreply, State};
handle_info(Msg, State) ->
	logger:warning("publisher handle unexpected msg:~p", [Msg]),
	{noreply, State}.

terminate(Reason, _State) ->
	logger:warning("publisher terminated by reason:~p", [Reason]),
	timer:sleep(3000),
	ok.

%% @private
connect(State) ->
	ConnProps = [{<<"connection_name">>, longstr, <<"publisher">>}],
	AmqpParams = #amqp_params_network{client_properties = ConnProps},
	{ok, AMQPConn} = amqp_connection:start(AmqpParams),
	{ok, AMQPChan} = amqp_connection:open_channel(AMQPConn),
	AMQPConnMRef = erlang:monitor(process, AMQPConn),
	AMQPChanMRef = erlang:monitor(process, AMQPChan),
	Declare = #'exchange.declare'{exchange = ?EXCHANGE, type = <<"topic">>, durable = true},
	#'exchange.declare_ok'{} = amqp_channel:call(AMQPChan, Declare),
	{ok, State#{channel => AMQPChan, amqp_conn_mref => AMQPConnMRef, amqp_chan_mref => AMQPChanMRef}}.