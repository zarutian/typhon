# Note that the identity "no-op" operation on ASTs is not `return ast` but
# rather `return M.call(maker, "run", args + [span])`; the transformation has
# to rebuild the AST.

def a := import("lib/monte/monte_ast")["astBuilder"]
def [=> term__quasiParser] := import("lib/monte/termParser")


def removeUnusedEscapes(ast, maker, args, span):
    "Remove unused escape clauses."

    if (ast.getNodeName() == "EscapeExpr"):
        def pattern := ast.getEjectorPattern()
        def node := ast.getBody()
        traceln(pattern.asTerm())
        # This limitation could be lifted but only with lots of care.
        if (pattern.getNodeName() == "FinalPattern" &&
            pattern.getGuard() == null):
            def name := pattern.getNoun().getName()
            traceln(name)
            def scope := node.getStaticScope()
            traceln(scope.namesUsed())
            if (!scope.namesUsed().contains(name)):
                traceln(`Success, I think?`)
                # We can just return the inner node directly.
                return node

    return M.call(maker, "run", args + [span])


def removeUnusedBareNouns(ast, maker, args, span):
    "Remove unused bare nouns from sequences."

    if (ast.getNodeName() == "SeqExpr" && args[0].size() > 0):
        def exprs := args[0]
        def last := exprs.last()
        def newExprs := [].diverge()
        for expr in exprs.slice(0, exprs.size() - 1):
            if (expr.getNodeName() != "NounExpr"):
                newExprs.push(expr)
        newExprs.push(last)
        return maker(newExprs.snapshot(), span)

    # No-op.
    return M.call(maker, "run", args + [span])

def testRemoveUnusedBareNouns(assert):
    def ast := a.SeqExpr([a.NounExpr("x", null), a.NounExpr("y", null)], null)
    def result := a.SeqExpr([a.NounExpr("y", null)], null)
    assert.equal(ast.transform(removeUnusedBareNouns), result)

unittest([testRemoveUnusedBareNouns])


def allSatisfy(pred, specimens) :Bool:
    "Return whether every specimen satisfies the predicate."
    for specimen in specimens:
        if (!pred(specimen)):
            return false
    return true


def map(f, xs):
    def rv := [].diverge()
    for x in xs:
        rv.push(f(x))
    return rv.snapshot()


def constantFoldLiterals(ast, maker, args, span):
    "Constant-fold calls to literals with literal arguments."

    if (ast.getNodeName() == "MethodCallExpr"):
        def receiver := ast.getReceiver()
        def argNodes := ast.getArgs()
        if (receiver.getNodeName() == "LiteralExpr" &&
            allSatisfy(fn x {x.getNodeName() == "LiteralExpr"}, argNodes)):
            def receiverValue := receiver.getValue()
            def verb := ast.getVerb()
            def argValues := map(fn x {x.getValue()}, argNodes)
            def constant := M.call(receiverValue, verb, argValues)
            return a.LiteralExpr(constant, span)

    # No-op.
    return M.call(maker, "run", args + [span])


def optimizations := [
    removeUnusedEscapes,
    removeUnusedBareNouns,
    constantFoldLiterals,
]


def optimize(var ast):
    for optimization in optimizations:
        ast := ast.transform(optimization)
    return ast


[=> optimize]