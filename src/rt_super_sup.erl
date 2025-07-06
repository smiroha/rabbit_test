-module(rt_super_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
	Tid = ets:new(?MODULE, [set, public, {read_concurrency, true}, {write_concurrency, true}]),
	Children = [
		#{
			id => rt_publisher,
			start => {rt_publisher, start_link, [Tid]},
			restart => permanent,
			shutdown => 5000,
			type => worker
		},
		#{
			id => rt_quorum_consumer,
			start => {rt_quorum_consumer, start_link, [Tid]},
			restart => permanent,
			shutdown => 5000,
			type => worker
		},
		#{
			id => rt_classic_consumer,
			start => {rt_classic_consumer, start_link, [Tid]},
			restart => permanent,
			shutdown => 5000,
			type => worker
		}
	],
	{ok, {{one_for_one, 10, 30}, Children}}.