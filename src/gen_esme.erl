-module(gen_esme).
-behaviour(gen_server).
-behaviour(gen_esme_session).

%%% INCLUDE FILES
-include_lib("oserl/include/oserl.hrl").

%%% BEHAVIOUR EXPORTS
-export([behaviour_info/1]).

%%% START/STOP EXPORTS
-export([start/3, start/4, start_link/3, start_link/4]).

%%% SERVER EXPORTS
-export([call/2, call/3, cast/2, reply/2]).

%%% CONNECT EXPORTS
-export([listen/2, open/3, close/1]).

%%% SMPP EXPORTS
-export([bind_receiver/3,
         bind_transceiver/3,
         bind_transmitter/3,
         broadcast_sm/3,
         cancel_broadcast_sm/3,
         cancel_sm/3,
         data_sm/3,
         query_broadcast_sm/3,
         query_sm/3,
         replace_sm/3,
         submit_multi/3,
         submit_sm/3,
         unbind/2]).

%%% LOG EXPORTS
-export([add_log_handler/3, delete_log_handler/3, swap_log_handler/3]).

%%% INIT/TERMINATE EXPORTS
-export([init/1, terminate/2]).

%%% HANDLE EXPORTS
-export([handle_call/3, handle_cast/2, handle_info/2]).

%%% CODE CHANGE EXPORTS
-export([code_change/3]).

%%% INTERNAL GEN_ESME_SESSION EXPORTS
-export([handle_accept/2,
         handle_alert_notification/2,
         handle_closed/2,
         handle_enquire_link/2,
         handle_operation/2,
         handle_outbind/2,
         handle_resp/3,
         handle_unbind/2]).

%%% RECORDS
-record(st, {mod, mod_st, ref, session, consumer, log, response_time}).

%%%-----------------------------------------------------------------------------
%%% BEHAVIOUR EXPORTS
%%%-----------------------------------------------------------------------------
behaviour_info(callbacks) ->
    [{init, 1},
     {terminate, 2},
     {handle_call, 3},
     {handle_cast, 2},
     {handle_info, 2},
     {code_change, 3},
     {handle_accept, 3},
     {handle_alert_notification, 2},
     {handle_closed, 2},
     {handle_data_sm, 3},
     {handle_deliver_sm, 2},
     {handle_outbind, 2},
     {handle_req, 4},
     {handle_resp, 3},
     {handle_unbind, 3}];
behaviour_info(_Other) ->
    undefined.

%%%-----------------------------------------------------------------------------
%%% START/STOP EXPORTS
%%%-----------------------------------------------------------------------------
start(Module, Args, Opts) ->
    gen_server:start(?MODULE, {Module, Args, []}, Opts).

start(SrvName, Module, Args, Opts) ->
    gen_server:start(SrvName, ?MODULE, {Module, Args, []}, Opts).

start_link(Module, Args, Opts) ->
    gen_server:start_link(?MODULE, {Module, Args, []}, Opts).

start_link(SrvName, Module, Args, Opts) ->
    gen_server:start_link(SrvName, ?MODULE, {Module, Args, []}, Opts).

%%%-----------------------------------------------------------------------------
%%% SERVER EXPORTS
%%%-----------------------------------------------------------------------------
call(SrvRef, Req) ->
    gen_server:call(SrvRef, {call, Req}).

call(SrvRef, Req, Timeout) ->
    gen_server:call(SrvRef, {call, Req}, Timeout).


cast(SrvRef, Req) ->
    gen_server:cast(SrvRef, {cast, Req}).


reply(Client, Reply) ->
    gen_server:reply(Client, Reply).

%%%-----------------------------------------------------------------------------
%%% CONNECT EXPORTS
%%%-----------------------------------------------------------------------------
listen(SrvRef, Opts) ->
    Pid = ref_to_pid(SrvRef),
    case smpp_session:listen(Opts) of
        {ok, LSock} ->
            ok = gen_tcp:controlling_process(LSock, Pid),
            Timers = proplists:get_value(timers, Opts, ?DEFAULT_TIMERS_SMPP),
            ListenOpts = [{lsock, LSock}, {timers, Timers}],
            gen_server:call(Pid, {start_session, ListenOpts}, ?ASSERT_TIME);
        Error ->
            Error
    end.

open(SrvRef, Addr, Opts) ->
    Pid = ref_to_pid(SrvRef),
    case proplists:get_value(sock, Opts) of
        undefined -> ok;
        Sock      -> ok = gen_tcp:controlling_process(Sock, Pid)
    end,
    gen_server:call(Pid, {start_session, [{addr, Addr} | Opts]}, ?ASSERT_TIME).

close(SrvRef) ->
    gen_server:cast(SrvRef, close).

%%%-----------------------------------------------------------------------------
%%% SMPP EXPORTS
%%%-----------------------------------------------------------------------------
bind_receiver(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{bind_receiver, Params}, Args}).

bind_transceiver(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{bind_transceiver, Params}, Args}).

bind_transmitter(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{bind_transmitter, Params}, Args}).

broadcast_sm(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{broadcast_sm, Params}, Args}).

cancel_broadcast_sm(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{cancel_broadcast_sm, Params}, Args}).

cancel_sm(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{cancel_sm, Params}, Args}).

data_sm(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{data_sm, Params}, Args}).

query_broadcast_sm(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{query_broadcast_sm, Params}, Args}).

query_sm(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{query_sm, Params}, Args}).

replace_sm(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{replace_sm, Params}, Args}).

submit_multi(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{submit_multi, Params}, Args}).

submit_sm(SrvRef, Params, Args) ->
    gen_server:cast(SrvRef, {{submit_sm, Params}, Args}).

unbind(SrvRef, Args) ->
    gen_server:cast(SrvRef, {{unbind, []}, Args}).

%%%-----------------------------------------------------------------------------
%%% LOG EXPORTS
%%%-----------------------------------------------------------------------------
add_log_handler(SrvRef, Handler, Args) ->
    gen_server:call(SrvRef, {add_log_handler, Handler, Args}, infinity).


delete_log_handler(SrvRef, Handler, Args) ->
    gen_server:call(SrvRef, {delete_log_handler, Handler, Args}, infinity).


swap_log_handler(SrvRef, Handler1, Handler2) ->
    gen_server:call(SrvRef, {swap_log_handler, Handler1, Handler2}, infinity).

%%%-----------------------------------------------------------------------------
%%% INIT/TERMINATE EXPORTS
%%%-----------------------------------------------------------------------------
init({Mod, Args, _Opts}) ->
    ResponseTime = proplists:get_value(response_time, Args, ?RESPONSE_TIME div 1000),
    {ok, Log} = smpp_log_mgr:start_link(),
    St = #st{mod = Mod, log = Log, response_time = timer:seconds(ResponseTime)},
    pack((St#st.mod):init(Args), St).

terminate(Reason, St) ->
    (St#st.mod):terminate(Reason, St#st.mod_st).

%%%-----------------------------------------------------------------------------
%%% HANDLE EXPORTS
%%%-----------------------------------------------------------------------------
handle_call({call, Req}, From, St) ->
    pack((St#st.mod):handle_call(Req, From, St#st.mod_st), St);
handle_call({start_session, Opts}, _From, St) ->
    NewOpts = [{log, St#st.log}, {timers, #timers_smpp{response_time = St#st.response_time}} | Opts],
    case gen_esme_session:start_link(?MODULE,  NewOpts) of
        {ok, Pid} ->
            Ref = erlang:monitor(process, Pid),
            unlink(Pid),
            {reply, ok, St#st{ref = Ref, session = Pid}};
        Error ->
            {reply, Error, St}
    end;
handle_call({add_log_handler, Handler, Args}, _From, St) ->
    {reply, smpp_log_mgr:add_handler(St#st.log, Handler, Args), St};
handle_call({delete_log_handler, Handler, Args}, _From, St) ->
    {reply, smpp_log_mgr:delete_handler(St#st.log, Handler, Args), St};
handle_call({swap_log_handler, Handler1, Handler2}, _From, St) ->
    {reply, smpp_log_mgr:swap_handler(St#st.log, Handler1, Handler2), St};
handle_call({handle_accept, Addr}, From, St) ->
    pack((St#st.mod):handle_accept(Addr, From, St#st.mod_st), St);
handle_call({handle_data_sm, Pdu}, From, St) ->
    pack((St#st.mod):handle_data_sm(Pdu, From, St#st.mod_st), St);
%handle_call({handle_deliver_sm, Pdu}, From, St) ->
%    pack((St#st.mod):handle_deliver_sm(Pdu, From, St#st.mod_st), St);
handle_call({handle_unbind, Pdu}, From, St) ->
    pack((St#st.mod):handle_unbind(Pdu, From, St#st.mod_st), St);
handle_call({handle_enquire_link, _Pdu}, _From, St) ->
    {reply, ok, St}.


handle_cast({cast, Req}, St) ->
    pack((St#st.mod):handle_cast(Req, St#st.mod_st), St);
handle_cast(close, St) ->
    try
        true = is_process_alive(St#st.session),
        ok = gen_esme_session:stop(St#st.session)
    catch
        error:_SessionNotAlive ->
            ok
    end,
    {noreply, St};
handle_cast({{CmdName, Params} = Req, Args}, St) ->
    Ref = req_send(St#st.session, CmdName, Params),
    pack((St#st.mod):handle_req(Req, Args, Ref, St#st.mod_st), St);
handle_cast({handle_deliver_sm, Pdu}, St) ->
    pack((St#st.mod):handle_deliver_sm(Pdu, St#st.mod_st), St);
handle_cast({handle_closed, Reason}, St) ->
    NewSt = session_closed(St),
    pack((NewSt#st.mod):handle_closed(Reason, NewSt#st.mod_st), NewSt);
handle_cast({handle_outbind, Pdu}, St) ->
    pack((St#st.mod):handle_outbind(Pdu, St#st.mod_st), St);
handle_cast({handle_resp, Resp, Ref}, St) ->
    pack((St#st.mod):handle_resp(Resp, Ref, St#st.mod_st), St);
handle_cast({handle_alert_notification, Pdu}, St) ->
    pack((St#st.mod):handle_alert_notification(Pdu, St#st.mod_st), St);
handle_cast({handle_enquire_link, _Pdu}, St) ->
    {noreply, St}.


handle_info({'DOWN', _Ref, _Type, Pid, Reason}, #st{session = Pid} = St) ->
    NewSt = session_closed(St),
    pack((NewSt#st.mod):handle_closed(Reason, NewSt#st.mod_st), NewSt);
handle_info(Info, St) ->
    pack((St#st.mod):handle_info(Info, St#st.mod_st), St).

%%%-----------------------------------------------------------------------------
%%% CODE CHANGE EXPORTS
%%%-----------------------------------------------------------------------------
code_change(OldVsn, St, Extra) ->
    pack((St#st.mod):code_change(OldVsn, St#st.mod_st, Extra), St).

%%%-----------------------------------------------------------------------------
%%% INTERNAL GEN_ESME_SESSION EXPORTS
%%%-----------------------------------------------------------------------------
handle_accept(SrvRef, Addr) ->
    gen_server:call(SrvRef, {handle_accept, Addr}, ?ASSERT_TIME).


handle_alert_notification(SrvRef, Pdu) ->
    gen_server:cast(SrvRef, {handle_alert_notification, Pdu}).


handle_closed(SrvRef, Reason) ->
    gen_server:cast(SrvRef, {handle_closed, Reason}).


handle_enquire_link(SrvRef, Pdu) ->
    gen_server:call(SrvRef, {handle_enquire_link, Pdu}, ?ASSERT_TIME).


handle_operation(SrvRef, {data_sm, Pdu}) ->
    gen_server:call(SrvRef, {handle_data_sm, Pdu}, ?ASSERT_TIME);
handle_operation(SrvRef, {deliver_sm, {_,_,_, L} = Pdu}) ->
    gen_server:cast(SrvRef, {handle_deliver_sm, Pdu}),
    MsgId = proplists:get_value(receipted_message_id, L),
    {ok, [{message_id, MsgId}]}.
%handle_operation(SrvRef, {deliver_sm, Pdu}) ->
%    gen_server:call(SrvRef, {handle_deliver_sm, Pdu}, ?ASSERT_TIME).


handle_outbind(SrvRef, Pdu) ->
    gen_server:cast(SrvRef, {handle_outbind, Pdu}).


handle_resp(SrvRef, Resp, Ref) ->
    gen_server:cast(SrvRef, {handle_resp, Resp, Ref}).


handle_unbind(SrvRef, Pdu) ->
    gen_server:call(SrvRef, {handle_unbind, Pdu}, ?ASSERT_TIME).

%%%-----------------------------------------------------------------------------
%%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------
pack({reply, Reply, ModSt}, St) ->
    {reply, Reply, St#st{mod_st = ModSt}};
pack({reply, Reply, ModSt, Timeout}, St) ->
    {reply, Reply, St#st{mod_st = ModSt}, Timeout};
pack({noreply, ModSt}, St) ->
    {noreply, St#st{mod_st = ModSt}};
pack({noreply, ModSt, Timeout}, St) ->
    {noreply, St#st{mod_st = ModSt}, Timeout};
pack({stop, Reason, Reply, ModSt}, St) ->
    {stop, Reason, Reply, St#st{mod_st = ModSt}};
pack({stop, Reason, ModSt}, St) ->
    {stop, Reason,  St#st{mod_st = ModSt}};
pack({ok, ModSt}, St) ->
    {ok, St#st{mod_st = ModSt}};
pack({ok, ModSt, Timeout}, St) ->
    {ok, St#st{mod_st = ModSt}, Timeout};
pack(Other, _St) ->
    Other.

ref_to_pid(Ref) when is_pid(Ref) ->
    Ref;
ref_to_pid(Ref) when is_atom(Ref) ->
    whereis(Ref);
ref_to_pid({global, Name}) ->
    global:whereis_name(Name);
ref_to_pid({Name, Node}) ->
    rpc:call(Node, erlang, whereis, [Name]).


req_send(Pid, CmdName, Params) ->
    try   % Need to protect ourselves to make sure that handle_closed is called
        if
            CmdName == bind_receiver ->
                gen_esme_session:bind_receiver(Pid, Params);
            CmdName == bind_transceiver ->
                gen_esme_session:bind_transceiver(Pid, Params);
            CmdName == bind_transmitter ->
                gen_esme_session:bind_transmitter(Pid, Params);
            CmdName == broadcast_sm ->
                gen_esme_session:broadcast_sm(Pid, Params);
            CmdName == cancel_broadcast_sm ->
                gen_esme_session:cancel_broadcast_sm(Pid, Params);
            CmdName == cancel_sm ->
                gen_esme_session:cancel_sm(Pid, Params);
            CmdName == data_sm ->
                gen_esme_session:data_sm(Pid, Params);
            CmdName == query_broadcast_sm ->
                gen_esme_session:query_broadcast_sm(Pid, Params);
            CmdName == query_sm ->
                gen_esme_session:query_sm(Pid, Params);
            CmdName == replace_sm ->
                gen_esme_session:replace_sm(Pid, Params);
            CmdName == submit_multi ->
                gen_esme_session:submit_multi(Pid, Params);
            CmdName == submit_sm ->
                gen_esme_session:submit_sm(Pid, Params);
            CmdName == unbind ->
                gen_esme_session:unbind(Pid)
        end
    catch
        _Any:{Reason, _Stack} -> % Session not alive or request malformed
            Ref = make_ref(),
            handle_resp(self(), {error, Reason}, Ref),
            Ref
    end.


session_closed(St) ->
    try
        erlang:demonitor(St#st.ref, [flush]),
        true = is_process_alive(St#st.consumer),
        ok = cl_consumer:stop(St#st.consumer)
    catch
        error:_NotAlive ->
            ok
    end,
    St#st{ref = undefined, session = undefined, consumer = undefined}.

