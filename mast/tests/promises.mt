import "unittest" =~ [=> unittest :Any]
exports ()

def testHarnessEventualSend(_assert):
    return 6<-multiply(7)

def testHarnessWhenNull(_assert):
    return when (null) -> { null }

def testHarnessWhenSend(_assert):
    return when (6<-multiply(7)) -> { null }

def testHarnessPromise(_assert):
    def [p, r] := Ref.promise()
    r.resolve(42)
    return p

def testHarnessPromiseLater(_assert):
    def [p, r] := Ref.promise()
    r<-resolve(42)
    return p

def testHarnessWhenPromise(_assert):
    def [p, r] := Ref.promise()
    r.resolve(42)
    return when (p) -> { null }

def testHarnessWhenPromiseLater(_assert):
    def [p, r] := Ref.promise()
    r<-resolve(42)
    return when (p) -> { null }

unittest([
    testHarnessEventualSend,
    testHarnessWhenNull,
    testHarnessWhenSend,
    testHarnessPromise,
    testHarnessPromiseLater,
    testHarnessWhenPromise,
    testHarnessWhenPromiseLater,
])

def vowInt(assert):
    def [p :Vow[Int], r] := Ref.promise()
    r.resolve(42)
    return when (p) -> { assert.equal(p, 42) }

def vowIntBroken(assert):
    def [p :Vow[Int], r] := Ref.promise()
    r.smash("test")
    return when (p) -> { assert.equal(p, 42) } catch _ {
        assert.equal(true, Ref.isBroken(p))
        assert.equal("test", Ref.optProblem(p))
    }

unittest([
    vowInt,
    vowIntBroken,
])
