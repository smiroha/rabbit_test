-module(rt_super_sup).

-behaviour(supervisor).

-define(CHILD(Id, M, F, A), #{id => Id, start => {M, F, A}, restart => permanent, shutdown => 5000, type => worker}).
-define(DEF_P_CNT, 3).
-define(DEF_Q_CON_CNT, 5).
-define(DEF_C_CNT, 5).

-export([start_link/0, init/1]).


start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).


init([]) ->
	Tid = ets:new(?MODULE, [set, public, {read_concurrency, true}, {write_concurrency, true}]),
	PubSpecs     = [make_spec(rt_publisher,        I, Tid) || I <- lists:seq(1, ?DEF_P_CNT)],
	QuorumSpecs  = [make_spec(rt_quorum_consumer,  I, Tid) || I <- lists:seq(1, ?DEF_Q_CON_CNT)],
	ClassicSpecs = [make_spec(rt_classic_consumer, I, Tid) || I <- lists:seq(1, ?DEF_C_CNT)],
	{ok, {{one_for_one, 10, 30}, PubSpecs ++ QuorumSpecs ++ ClassicSpecs}}.


%% @private
make_spec(Module, Index, Tid) ->
	Name = binary_to_atom(<< (atom_to_binary(Module))/binary, "_", (integer_to_binary(Index))/binary>>),
	?CHILD(Name, Module, start_link, [Name, Tid]).
