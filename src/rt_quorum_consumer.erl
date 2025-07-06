-module(rt_quorum_consumer).

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

handle_info({#'basic.deliver'{}, {amqp_msg, #'P_basic'{}, Content}}, State = #{name := Name, tid := Tid}) ->
	#{from := From, seq := Seq} = binary_to_term(Content),
	Last = ets:update_counter(Tid, {Name, From}, {2, 1}, {{Name, From}, 0}),
	case Seq =:= Last of
		true -> ok;
		_ ->
			logger:error("consumer:~p from:~p compare 'seq' resulted in error - seq:~p last:~p diff:~p",
				[Name, From, Seq, Last, Last-Seq]),
			true = ets:insert(Tid, {{Name, From}, Seq})
	end,
	if Seq rem 1000 =:= 0 -> logger:info("consumer:~p from:~p reached seq:~p", [Name, From, Seq]); true -> ok end,
	{noreply, State};
handle_info(#'basic.consume_ok'{}, State) -> {noreply, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_conn_mref := MRef}) -> {stop, {died_conn, Reason}, State};
handle_info({'DOWN', MRef, _, _Pid, Reason}, State = #{amqp_chan_mref := MRef}) -> {stop, {died_chan, Reason}, State};
handle_info(connect, OldState = #{name := Name, tid := Tid}) ->
	{ok, State} = connect(OldState),
	logger:info("consumer:~p (re)connected seq:~p", [Name, ets:match(Tid, {{Name, '_'}, '_'})]),
	{noreply, State};
handle_info(Msg, State = #{name := Name}) ->
	logger:warning("consumer:~p handle unexpected msg:~p", [Name, Msg]),
	{noreply, State}.

terminate(Reason, #{name := Name}) ->
	logger:warning("consumer:~p terminated by reason:~p", [Name, Reason]),
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
	Queue = <<"rb_quorum_queue_", (atom_to_binary(Name))/binary>>,
	Args = [{<<"x-queue-type">>, longstr, <<"quorum">>}],
	Declare = #'queue.declare'{queue = Queue, durable = true, arguments = Args},
	Bind = #'queue.bind'{queue = Queue, exchange = ?EXCHANGE},
	Consume = #'basic.consume'{queue = Queue, no_ack = true},
	#'queue.declare_ok'{} = amqp_channel:call(AMQPChan, Declare),
	#'queue.bind_ok'{} = amqp_channel:call(AMQPChan, Bind),
	#'basic.consume_ok'{} = amqp_channel:call(AMQPChan, Consume),
	{ok, State#{amqp_conn_mref => AMQPConnMRef, amqp_chan_mref => AMQPChanMRef}}.