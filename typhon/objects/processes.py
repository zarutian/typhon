import os
import signal

from rpython.rlib.rarithmetic import intmask
from rpython.rtyper.lltypesystem.lltype import nullptr

from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import userError
from typhon.objects.collections.maps import monteMap
from typhon.objects.data import BytesObject, StrObject, unwrapBytes
from typhon.objects.networking.streamcaps import (StreamSink, StreamSource,
                                                  emptySource, nullSink)
from typhon.objects.root import Object, audited
from typhon.objects.refs import makePromise
from typhon.vats import currentVat, scopedVat


FLOWTO_1 = getAtom(u"flowTo", 1)
RUN_3 = getAtom(u"run", 3)


@autohelp
class CurrentProcess(Object):
    """
    The current process on the local node.
    """

    def __init__(self, config):
        self.config = config

    def toString(self):
        return u"<current process (PID %d)>" % os.getpid()

    @method("List")
    def getArguments(self):
        return [StrObject(arg.decode("utf-8")) for arg in self.config.argv]

    @method("Map")
    def getEnvironment(self):
        # XXX monteMap()
        d = monteMap()
        for key, value in os.environ.items():
            k = BytesObject(key)
            v = BytesObject(value)
            d[k] = v
        return d

    @method("Int")
    def getPID(self):
        return os.getpid()

    @method("Void")
    def interrupt(self):
        os.kill(os.getpid(), signal.SIGINT)


@autohelp
class ProcessExitInformation(Object):
    """
    Holds a process' exitStatus and terminationSignal
    """

    def __init__(self, exitStatus, terminationSignal):
        self._exitStatus = exitStatus
        self._terminationSignal = terminationSignal

    def toString(self):
        return (u'<ProcessExitInformation exitStatus=%d,'
                u' terminationSignal=%d>' % (self._exitStatus,
                                             self._terminationSignal))

    @method("Int")
    def exitStatus(self):
        return self._exitStatus

    @method("Int")
    def terminationSignal(self):
        return self._terminationSignal


@autohelp
class SubProcess(Object):
    """
    A subordinate process of the current process, on the local node.
    """
    EMPTY_PID = -1
    EMPTY_EXIT_AND_SIGNAL = (-1, -1)

    def __init__(self, vat, process, argv, env, stdin, stdout, stderr):
        self.pid = self.EMPTY_PID
        self.process = process
        self.argv = argv
        self.env = env
        self.exit_and_signal = self.EMPTY_EXIT_AND_SIGNAL
        self.resolvers = []
        self.vat = vat

        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr

        ruv.stashProcess(process, (self.vat, self))

    def retrievePID(self):
        if self.pid == self.EMPTY_PID:
            self.pid = intmask(self.process.c_pid)

    def exited(self, exit_status, term_signal):
        if self.pid == self.EMPTY_PID:
            self.retrievePID()
        self.exit_and_signal = (intmask(exit_status), intmask(term_signal))
        toResolve, self.resolvers = self.resolvers, []

        with scopedVat(self.vat):
            for resolver in toResolve:
                self.resolveWaiter(resolver)

    def resolveWaiter(self, resolver):
        resolver.resolve(ProcessExitInformation(*self.exit_and_signal))

    def toString(self):
        if self.pid == self.EMPTY_PID:
            return u"<child process (unspawned)>"
        return u"<child process (PID %d)>" % self.pid

    @method("List")
    def getArguments(self):
        return [BytesObject(arg) for arg in self.argv]

    @method("Map")
    def getEnvironment(self):
        # XXX monteMap()
        d = monteMap()
        for key, value in self.env.items():
            k = BytesObject(key)
            v = BytesObject(value)
            d[k] = v
        return d

    @method("Int")
    def getPID(self):
        return self.pid

    @method("Void")
    def interrupt(self):
        os.kill(self.pid, signal.SIGINT)

    @method("Any")
    def wait(self):
        p, r = makePromise()
        if self.exit_and_signal != self.EMPTY_EXIT_AND_SIGNAL:
            self.resolveWaiter(r)
        else:
            self.resolvers.append(r)
        return p

    @method("Any")
    def stdin(self):
        return self.stdin

    @method("Any")
    def stdout(self):
        return self.stdout

    @method("Any")
    def stderr(self):
        return self.stderr


@autohelp
@audited.DF
class makeProcess(Object):
    """
    Create a subordinate process on the current node from the given
    executable, arguments, and environment.

    `=> stdin`, `=> stdout`, and `=> stderr` control the same-named methods on
    the resulting process object, which will return a sink, source, and source
    respectively. If any of these named arguments are `true`, then the
    corresponding method on the process will return a live streamcap which
    is connected to the process; otherwise, the returned streamcap will be a
    no-op.
    """

    @method("Any", "Bytes", "List", "Map", stdin="Bool", stdout="Bool",
            stderr="Bool")
    def run(self, executable, argv, env, stdinFount=None, stdoutDrain=None,
            stderrDrain=None, stdin=False, stdout=False, stderr=False):
        # Sixth incarnation: Now with streamcaps!

        # Unwrap argv.
        l = []
        for arg in argv:
            bs = unwrapBytes(arg)
            assert bs is not None, "proven impossible"
            l.append(bs)
        argv = l

        # Unwrap and prep environment.
        d = {}
        for (k, v) in env.items():
            d[unwrapBytes(k)] = unwrapBytes(v)
        packedEnv = [k + '=' + v for (k, v) in d.items()]
        env = d

        vat = currentVat.get()

        # Set up the list of streams and attach streamcaps.
        stdinSink = nullSink
        stdoutSource = stderrSource = emptySource
        streams = []
        if stdin:
            stream = ruv.rffi.cast(ruv.stream_tp,
                                   ruv.alloc_pipe(vat.uv_loop))
            streams.append(stream)
            wrapped = ruv.wrapStream(stream, 1)
            stdinSink = StreamSink(wrapped, vat)
        else:
            streams.append(nullptr(ruv.stream_t))
        if stdout:
            stream = ruv.rffi.cast(ruv.stream_tp,
                                   ruv.alloc_pipe(vat.uv_loop))
            streams.append(stream)
            wrapped = ruv.wrapStream(stream, 1)
            stdoutSource = StreamSource(wrapped, vat)
        else:
            streams.append(nullptr(ruv.stream_t))
        if stderr:
            stream = ruv.rffi.cast(ruv.stream_tp,
                                   ruv.alloc_pipe(vat.uv_loop))
            streams.append(stream)
            wrapped = ruv.wrapStream(stream, 1)
            stderrSource = StreamSource(wrapped, vat)
        else:
            streams.append(nullptr(ruv.stream_t))

        try:
            process = ruv.allocProcess()
            sub = SubProcess(vat, process, argv, env, stdin=stdinSink,
                             stdout=stdoutSource, stderr=stderrSource)
            ruv.spawn(vat.uv_loop, process,
                      file=executable, args=argv, env=packedEnv,
                      streams=streams)
            sub.retrievePID()
            return sub
        except ruv.UVError as uve:
            raise userError(u"makeProcess: Couldn't spawn process: %s" %
                            uve.repr().decode("utf-8"))
