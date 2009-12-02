%% ---
%%  Excerpted from "Programming Erlang",
%%  published by The Pragmatic Bookshelf.
%%  Copyrights apply to this code. It may not be used to create training material, 
%%  courses, books, articles, and the like. Contact us if you are in doubt.
%%  We make no guarantees that this code is fit for any purpose. 
%%  Visit http://www.pragmaticprogrammer.com/titles/jaerlang for more book information.
%%
%% Original copyright: (c) 2007 armstrongonsoftware
%% 
%%---
-module(indexer_server).

-export([next_docs/1,
	 ets_table/1, 
	 checkpoint/1,
	 schedule_stop/1,
	 search/2,
         write_index/3,
	 should_i_stop/1,
	 stop/1]).

-export([init/1, handle_call/3, handle_cast/2, terminate/2]).
-import(filename, [join/2]).
-include("indexer.hrl").

schedule_stop(Pid) ->
    Check = gen_server:call(Pid, schedule_stop),
    case Check of
        ack -> ack;
        %% index is not running go ahead and stop now
        norun -> stop(Pid)
    end.

should_i_stop(Pid) ->
    gen_server:call(Pid, should_i_stop).

stop(Pid) ->
     gen_server:cast(Pid, stop).



next_docs(Pid)   -> gen_server:call(Pid, next_docs, infinity).
checkpoint(Pid) -> gen_server:call(Pid, checkpoint).
ets_table(Pid)  -> gen_server:call(Pid, ets_table).
    
search(Pid, Str)  -> gen_server:call(Pid, {search, Str}).

write_index(Pid, Key, Vals) ->
    gen_server:call(Pid, {write, Key, Vals}).

-record(env,
        {ets, 
         cont, 
         dbnam, 
         idx, 
         nextCP,
         chkp, 
         stop=false}).

init(DbName) ->
    Tab = indexer_trigrams:open(),
    DbIndexName = list_to_binary(DbName ++ "-idx"),
   
    case indexer_couchdb_crawler:db_exists(DbIndexName) of
        true -> ok;
        false ->
            Cont = indexer_couchdb_crawler:start(list_to_binary(DbName),[{reset, DbIndexName}]),
	    Check = {DbIndexName, Cont},
	    ?LOG(?INFO, "creating checkpoint:~p~n", [Check]),
	    indexer_checkpoint:init(DbIndexName, Check)
    end,
    
    {Next, {_, Cont1}} = indexer_checkpoint:resume(DbIndexName),
    ?LOG(?INFO, "resuming checkpoint: ~p ~p~n",[Next, Cont1]),
    
    {ok, #env{ets=Tab,
                      dbnam=list_to_binary(DbName),
                      idx=DbIndexName,
                      cont=Cont1,
                      nextCP=Next}}.

handle_call(ets_table, _From, S) ->
    {reply, S#env.ets, S};
handle_call(next_docs, _From, S) ->
    Cont = S#env.cont,
    case indexer_couchdb_crawler:next(Cont) of
	{docs, Docs, ContToCkP} ->
            ?LOG(?DEBUG, "checking the values in next docs ~p ~n",[ContToCkP]),
	    {reply, {ok, Docs}, S#env{chkp=ContToCkP}};
	done ->
	    {reply, done, S}
    end;
handle_call(checkpoint, _From, S) ->
    Next = S#env.nextCP,
    DbIndexName = S#env.idx,
    Next1 = indexer_checkpoint:checkpoint(Next, {DbIndexName, S#env.chkp}),
    ?LOG(?DEBUG, "the next checkpoint is ~p ~n",[Next1]),
    S1 = S#env{nextCP = Next1, cont=S#env.chkp},
    {reply, ok, S1};
handle_call(schedule_stop, _From, S) ->
    case S#env.chkp of
       {_, done} -> {reply, norun, S};
        _ -> {reply, ack, S#env{stop=true}}
    end;
handle_call({search, Str}, _From,S) ->
    Result = indexer_misc:search(Str, S#env.ets, S#env.dbnam, S#env.idx),
    {reply, Result, S};

handle_call({write, Key, Vals}, _From,S) ->
    Result = indexer_couchdb_crawler:write_indices(Key, Vals, S#env.idx),
    {reply, Result, S};

handle_call(should_i_stop, _From, S) ->
    {reply, S#env.stop, S}.

handle_cast(stop, S) ->
    {stop, normal, S}.

terminate(Reason, S) ->
    Ets = S#env.ets,
    indexer_trigrams:close(Ets),
    ?LOG(?INFO, "stopping ~p~n",[Reason]).



    



    


