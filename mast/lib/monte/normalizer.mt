exports (normalize, normalize0)

def normalize(ast, builder) as DeepFrozen:

    def normalizeTransformer(node, _maker, args, span):
        return switch (node.getNodeName()):
            match =="LiteralExpr":
                switch (args[0]):
                    match ==null:
                        builder.NullExpr(span)
                    match i :Int:
                        builder.IntExpr(i, span)
                    match s :Str:
                        builder.StrExpr(s, span)
                    match c :Char:
                        builder.CharExpr(c, span)
                    match d :Double:
                        builder.DoubleExpr(d, span)
            match =="AssignExpr":
                def [_name, rvalue] := args
                builder.AssignExpr(node.getLvalue().getName(), rvalue, span)
            match =="BindingExpr":
                builder.BindingExpr(node.getNoun().getName(), span)
            match =="CatchExpr":
                def [body, patt, catchbody] := args
                builder.TryExpr(body, patt, catchbody, span)
            match =="MethodCallExpr":
                def [obj, verb, margs, namedArgs] := args
                builder.CallExpr(obj, verb, margs, namedArgs, span)
            match =="EscapeExpr":
                if (args =~ [patt, body, ==null, ==null]):
                    builder.EscapeOnlyExpr(patt, body, span)
                else:
                    def [ejPatt, ejBody, catchPatt, catchBody] := args
                    builder.EscapeExpr(ejPatt, ejBody, catchPatt, catchBody, span)
            match =="ObjectExpr":
                def [doc, name, asExpr, auditors, [methods, matchers]] := args
                builder.ObjectExpr(if (doc == null) {""} else {doc}, name,
                                   [asExpr] + auditors, methods, matchers,
                                   span)
            match =="Script":
                def [_, methods, matchers] := args
                [methods, matchers]
            match =="IgnorePattern":
                def [guard] := args
                builder.IgnorePatt(guard, span)
            match =="BindingPattern":
                builder.BindingPatt(node.getNoun().getName(), span)
            match =="FinalPattern":
                def [_, guard] := args
                builder.FinalPatt(node.getNoun().getName(), guard, span)
            match =="VarPattern":
                def [_, guard] := args
                builder.VarPatt(node.getNoun().getName(), guard, span)
            match =="ListPattern":
                def [patts, _] := args
                builder.ListPatt(patts, span)
            match =="ViaPattern":
                def [expr, patt] := args
                builder.ViaPatt(expr, patt, span)
            match =="NamedArg":
                def [key, value] := args
                builder.NamedArgExpr(key, value, span)
            match =="NamedParam":
                def [k, p, d] := args
                builder.NamedPattern(k, p, d, span)
            match =="Matcher":
                def [patt, body] := args
                builder.MatcherExpr(patt, body, span)
            match =="Method":
                def [doc, verb, patts, namedPatts, guard, body] := args
                builder.MethodExpr(if (doc == null) {""} else {doc}, verb,
                                   patts, namedPatts, guard, body, span)
            match nodeName:
                M.call(builder, nodeName, args + [span], [].asMap())

    return ast.transform(normalizeTransformer)

def makeLetBinder(n, builder, [outerNames, &seq, parent]) as DeepFrozen:
    def letBindings := [].diverge()
    return object letBinder:
        to getI(ast0):
            return n.immediate(ast0, builder, letBinder)
        to getC(ast0):
            return n.complex(ast0, builder, letBinder)
        to getP(patt, exit_, expr):
            n.pattern(patt, exit_, expr, builder, letBinder)
        to addBinding(name :Str, bindingExpr, span):
            for [_, _, lname, lspan] in (letBindings):
                if (lname != "" && lname == name):
                    throw(`Error at $span: "$name" already defined at $lspan`)
            letBindings.push([seq += 1, bindingExpr, name, span])
            return seq
        to addTempBinding(bindingExpr, span):
            return letBinder.addBinding("", builder.TempBinding(bindingExpr, span), span)
        to getDefs():
            return [outerNames, &seq, letBinder]
        to getSeq():
            return seq
        to getBindings():
            return letBindings
        to getIndexFor(name, span):
            for [idx, binding, lname, _] in (letBindings):
                if (lname == name):
                    return idx
            if (parent == null):
                if ((def i := outerNames.indexOf(name)) >= 0):
                    return i
                throw(`Undefined name $name at $span`)

            return parent.getIndexFor(name, span)

        to guardCoerceFor(speci, gi, ei, span):
            return builder.TempExpr(
                letBinder.addTempBinding(builder.GuardCoerce(speci, gi, ei, span), span), span)
        to letExprFor(expr, span):
            return if (letBindings.isEmpty()) {
                expr
            } else if (expr.getNodeName() == "TempExpr" &&
                       (letBindings.last()[0] == expr.getIndex())) {
                if (letBindings.size() == 1) {
                    letBindings[0][1].getValue()
                } else {
                    builder.LetExpr([for args in
                                 (letBindings.slice(0, letBindings.size() - 1))
                                 M.call(builder, "LetDef", args, [].asMap())],
                                letBindings.last()[1].getValue(), span)
                }
            } else {
                builder.LetExpr([for args in (letBindings)
                                 M.call(builder, "LetDef", args, [].asMap())],
                                expr, span)
            }

def makeParamBinder(count, [outerNames, &seq, parent]) as DeepFrozen:
    def paramBindings := [for _ in (0..!count) seq += 1]
    object paramBinder:
        to getIndexFor(name, span):
            return parent.getIndexFor(name, span)
        to getDefs():
            return [outerNames, &seq, parent]
    return [paramBinder, paramBindings]

object normalize0 as DeepFrozen:
    to run(ast, outerNames, builder):
        var gensym_seq :Int := outerNames.size() - 1
        return normalize0.normalize(ast, builder, [outerNames, &gensym_seq, null])

    to normalize(ast, builder, defs):
        def binder := makeLetBinder(normalize0, builder, defs)
        def expr := normalize0.immediate(ast, builder, binder)
        return binder.letExprFor(expr, ast.getSpan())

    to immediate(ast, builder, binder):
        def nn := ast.getNodeName()
        def span := ast.getSpan()
        if (nn == "LiteralExpr"):
            return switch (ast.getValue()) {
                match ==null  {builder.NullExpr(span)}
                match i :Int  {builder.IntExpr(i, span)}
                match s :Str  {builder.StrExpr(s, span)}
                match c :Char {builder.CharExpr(c, span)}
                match d :Double {builder.DoubleExpr(d, span)}
                match v {throw("Unknown literal " + M.toQuote(v))}
            }
        else if (nn == "NounExpr"):
            if (ast.getName() == "null"):
                return builder.NullExpr(span)
            return builder.NounExpr(
                def n := ast.getName(),
                binder.getIndexFor(n, span),
                span)
        else if (nn == "BindingExpr"):
            return builder.BindingExpr(
                def n := ast.getNoun().getName(),
                binder.getIndexFor(n, span),
                span)
        else if (nn == "MetaContextExpr"):
            return builder.MetaContextExpr()
        else if (nn == "MetaStateExpr"):
            return builder.MetaStateExpr()
        else:
            return builder.TempExpr(
                binder.addTempBinding(normalize0.complex(ast, builder, binder), span),
                span)

    to complex(ast, builder, binder):
        def span := ast.getSpan()
        def nn := ast.getNodeName()
        if (nn == "AssignExpr"):
            def bi := binder.addTempBinding(
                builder.CallExpr(
                    builder.BindingExpr(def n := ast.getLvalue().getName(),
                                        binder.getIndexFor(n, span),
                                        span),
                    "get", [], [], span), span)
            return builder.CallExpr(
                builder.TempExpr(bi, span),
                "put", [binder.getI(ast.getRvalue())], [], span)
        else if (nn == "DefExpr"):
            def expr := binder.getI(ast.getExpr())
            def ei := if ((def ex := ast.getExit()) != null) {
                binder.getI(ex)
            } else { null }
            binder.getP(ast.getPattern(), ei, expr)
            return expr
        else if (nn == "EscapeExpr"):
            def [paramBox, [ei]] := makeParamBinder(1, binder.getDefs())
            def innerBinder := makeLetBinder(normalize0, builder, paramBox.getDefs())
            innerBinder.getP(ast.getEjectorPattern(), null, builder.TempExpr(ei, span))
            def b := innerBinder.letExprFor(innerBinder.getC(ast.getBody()), span)
            if (ast.getCatchPattern() == null):
                return builder.EscapeOnlyExpr(ei, b, span)
            else:
                def [paramBox, [pi]] := makeParamBinder(1, binder.getDefs())
                def catchBinder := makeLetBinder(normalize0, builder, paramBox.getDefs())
                catchBinder.getP(ast.getCatchPattern(), null, builder.TempExpr(pi, span))
                def cb := catchBinder.letExprFor(catchBinder.getC(ast.getCatchBody()),
                                                 span)
                return builder.EscapeExpr(ei, b, pi, cb, span)
        else if (nn == "FinallyExpr"):
            return builder.FinallyExpr(
                normalize0.normalize(ast.getBody(), builder, binder.getDefs()),
                normalize0.normalize(ast.getUnwinder(), builder, binder.getDefs()),
                span)
        else if (nn == "HideExpr"):
            # XXX figure out a renaming scheme to avoid inner-let
            return normalize0.normalize(ast.getBody(), builder, binder.getDefs())
        else if (nn == "MethodCallExpr"):
            def r := binder.getI(ast.getReceiver())
            def argList := [for arg in (ast.getArgs()) binder.getI(arg)]
            def namedArgList := [for na in (ast.getNamedArgs())
                                 builder.NamedArgExpr(binder.getI(na.getKey()),
                                                      binder.getI(na.getValue()),
                                                      na.getSpan())]
            return builder.CallExpr(r, ast.getVerb(), argList, namedArgList, span)
        else if (nn == "IfExpr"):
            def test := binder.getI(ast.getTest())
            def alt := normalize0.normalize(ast.getThen(), builder, binder.getDefs())
            def consq := switch (ast.getElse()) {
                match ==null {builder.NullExpr(span)}
                match e {normalize0.normalize(e, builder, binder.getDefs())}}
            return builder.IfExpr(test, alt, consq, span)
        else if (nn == "SeqExpr"):
            def exprs := ast.getExprs()
            for item in (exprs.slice(0, exprs.size() - 1)):
                binder.getI(item)
            return binder.getC(exprs.last())
        else if (nn == "CatchExpr"):
            def b := normalize0.normalize(ast.getBody(), builder, binder.getDefs())
            def [paramBox, [ci]] := makeParamBinder(1, binder.getDefs())
            def catchBinder := makeLetBinder(normalize0, builder, paramBox.getDefs())
            catchBinder.getP(ast.getPattern(), null, builder.TempExpr(ci, span))
            def cb := catchBinder.letExprFor(
                catchBinder.getC(ast.getCatcher()), span)
            return builder.TryExpr(b, ci, cb, span)
        else if (nn == "ObjectExpr"):
            def ai := if ((def asExpr := ast.getAsExpr()) != null) {
                [binder.getI(asExpr)]
            } else {
                [builder.NullExpr(span)]
            } + [for aud in (ast.getAuditors()) binder.getI(aud)]
            def objectBinding
            def oi := builder.TempExpr(binder.addBinding("", objectBinding, span), span)
            def op := ast.getName()
            # FinalPattern/VarPattern must be handled specially to implement 'as'.
            if (ast.getAsExpr() != null):
                if (op.getNodeName() == "FinalPattern"):
                    binder.addBinding(op.getNoun().getName(),
                                      builder.FinalBinding(oi, ai[0], span), span)
                else if (op.getNodeName() == "VarPattern"):
                    binder.addBinding(op.getNoun().getName(),
                                      builder.VarBinding(oi, ai[0], span), span)
                else:
                    throw("\"as\" in ObjectExpr not allowed with complex pattern")
            else:
                normalize0.pattern(op, null, oi, builder, binder)

            def methods := [].diverge()
            def matchers := [].diverge()
            for meth in (ast.getScript().getMethods()):
                def [paramBox, allParami] := makeParamBinder(meth.getParams().size() + 1,
                                                             binder.getDefs())
                def methBinder := makeLetBinder(normalize0, builder,
                                                paramBox.getDefs())
                def parami := allParami.slice(0, allParami.size() - 1)
                def namedParami := allParami.last()
                for i => p in (meth.getParams()):
                    methBinder.getP(p, null, builder.TempExpr(parami[i], span))
                for np in (meth.getNamedParams()):
                    def npi := methBinder.addTempBinding(builder.NamedParamExtract(
                        namedParami,
                        methBinder.getI(np.getKey()),
                        methBinder.getI(np.getDefault()), span), span)
                    methBinder.getP(np.getValue(), null,
                                    builder.TempExpr(npi, span))
                def g := meth.getResultGuard()
                def gb := if (g == null) {
                    methBinder.getC(meth.getBody())
                } else {
                    methBinder.guardCoerceFor(methBinder.getI(meth.getBody()),
                                              methBinder.getI(g),
                                              builder.NullExpr(span),
                                              span)
                }
                methods.push(
                    builder."Method"(meth.getDocstring(), meth.getVerb(),
                                     parami, namedParami,
                                     methBinder.letExprFor(gb, span), span))
            for matcher in (ast.getScript().getMatchers()):
                def [paramBox, [mi]] := makeParamBinder(1, binder.getDefs())
                def matcherBinder := makeLetBinder(normalize0, builder,
                                                   paramBox.getDefs())
                matcherBinder.getP(matcher.getPattern(), null,
                                   builder.TempExpr(mi, span))
                matchers.push(builder.Matcher(
                    mi, matcherBinder.letExprFor(
                        matcherBinder.getC(matcher.getBody()), span), span))
            bind objectBinding := builder.TempBinding(builder.ObjectExpr(
                ast.getDocstring(),
                ast, ai,
                methods.snapshot(),
                matchers.snapshot(),
                span), span)
            return oi
        else if (["LiteralExpr", "NounExpr", "BindingExpr", "MetaStateExpr", "MetaContextExpr"].contains(nn)):
            return normalize0.immediate(ast, builder, binder)
        else:
            throw(`Unrecognized node $ast (type ${try {ast.getNodeName()} catch _ {"unknown"}})`)

    to pattern(p, exitNode, si, builder, binder):
        def span := p.getSpan()
        def ei := if (exitNode == null) {
            builder.NullExpr(span)
        } else {
            exitNode
        }
        def pn := p.getNodeName()

        def matchSlot(slotNode):
            var si2 := si
            var gi := builder.NullExpr(span)
            if ((def g := p.getGuard()) != null):
                gi := binder.getI(g)
                si2 := binder.guardCoerceFor(si, gi, ei, span)
            return binder.addBinding(
                p.getNoun().getName(),
                slotNode(si2, gi, span),
                span)


        if (pn == "FinalPattern"):
            matchSlot(builder.FinalBinding)
        else if (pn == "VarPattern"):
            matchSlot(builder.VarBinding)
        else if (pn == "BindingPattern"):
            binder.addBinding(p.getNoun().getName(), si, span)
        else if (pn == "IgnorePattern"):
            def gi := if ((def g := p.getGuard()) != null) {
                binder.getI(g)
            } else {
                builder.NullExpr(span)
            }
            binder.guardCoerceFor(si, gi, ei, span)
        else if (pn == "ListPattern"):
            def ps := p.getPatterns()
            def li := builder.TempExpr(
                binder.addTempBinding(builder.ListCoerce(
                    si, ps.size(), ei, span), span), span)
            for idx => subp in (ps):
                def subi := binder.addTempBinding(
                    builder.CallExpr(li, "get",
                                     [builder.IntExpr(idx, span)], [],
                                     span), span)
                binder.getP(subp, ei, builder.TempExpr(subi, span))
        else if (pn == "ViaPattern"):
            def vi := binder.getI(p.getExpr())
            def si2 := binder.addTempBinding(builder.CallExpr(
                vi, "run", [si, ei], [], span), span)
            binder.getP(p.getPattern(), exitNode, builder.TempExpr(si2, span))
        return binder.getBindings()

# Storage class. Binding and usage are used to determine how to store refs in
# the object frame.

def [NOUN :Int, BINDING :Int] := [0, 1]

def layoutScopes(ast, outerNames, builder, inRepl) as DeepFrozen:
    def allNames := [].asMap().diverge()
    def accessTypes := [].asMap().diverge()
    def _layoutScopes(ast):
        def layoutExprList(exprs):
            var freeNames := [].asSet()
            def newExprs := [].diverge()
            var localSize := 0
            for a in (ast.getAuditors):
                def [new, newFreeNames, ls] := _layoutScopes(a)
                freeNames |= newFreeNames
                localSize := localSize.max(ls)
                newExprs.push(new)
            return [newExprs, freeNames, localSize]
        def nn := ast.getNodeName()
        if (nn == "TempExpr"):
           return [builder.TempExpr(ast.getIndex(), ast.getSpan()), [].asSet(), 0]
        else if (nn == "LetExpr"):
            def newExprs := [].diverge()
            def newDefs := [].diverge()
            def boundNames := [].asSet()
            var freeNames := [].asSet()
            var subLocalSize := 0
            # Process all of the exprs in let defs, process the body, then go
            # through defs _again_ to construct final form with storage type
            # (NOUN, BINDING).
            for letdef in (ast.getDefs()):
                def binding := letdef.getExpr()
                if (!binding.getNodeName().endsWith("Binding")):
                    def [newBinding, bFreeNames, bLocalSize] := _layoutScopes(binding)
                    newExprs.push(newBinding)
                    freeNames |= bFreeNames
                    subLocalSize max= (bLocalSize)
                else:
                    def expr := binding.getValue()
                    def [newExpr, eFreeNames, eLocalSize] := _layoutScopes(expr)
                    freeNames |= eFreeNames
                    subLocalSize max= (eLocalSize)
                    def guard := if (["VarBinding", "FinalBinding"].contains(
                        binding.getNodeName())) {
                            def [newGuard, gf, gls] := _layoutScopes(binding.getGuard())
                            freeNames |= gf
                            subLocalSize max= (gls)
                            newGuard
                        } else { null }
                    newExprs.push([newExpr, guard])
            def [newBody, bFreeNames, bLocalSize] := _layoutScopes(ast.getBody())
            freeNames |= bFreeNames
            subLocalSize max= (bLocalSize)
            # All references to names bound in this LetExpr have now been seen.
            # We can now decide which bindings can be deslotified. Since
            # deslotification requires rewriting NounExprs, we leave that for a
            # future pass. Maybe.
            for i => letdef in (ast.getDefs()):
                def binding := letdef.getExpr()
                def bn := binding.getNodeName()
                if (bn == "TempBinding"):
                    def [newVal, ==null] := newExprs[i]
                    newDefs.push(builder.LetDef(
                        builder.TempBinding(newVal, binding.getSpan()),
                        letdef.getSpan()))
                else:
                    def newBinding := if (bn == "FinalBinding") {
                        def [newVal, newGuard] := newExprs[i]
                        builder.FinalBinding(newVal, newGuard,
                                             accessTypes[letdef.getIndex()],
                                             binding.getSpan())
                    } else if (bn == "VarBinding") {
                        def [newVal, newGuard] := newExprs[i]
                        builder.VarBinding(newVal, newGuard,
                                           accessTypes[letdef.getIndex()],
                                           binding.getSpan())
                    } else {
                        newExprs[i]
                    }
                    allNames[letdef.getIndex()] := [letdef.getName(), newExpr]
                    boundNames.include(letdef.getIndex())
                    newDefs.push(builder.LetDef(letdef.getIndex(), newBinding,
                                                letdef.getName(), letdef.getSpan()))
            return [builder.LetExpr(newDefs, newBody, ast.getSpan()),
                    freeNames &! boundNames,
                    boundNames.size() + subLocalSize]
        else if (nn == "ObjectExpr"):
            def [newAuditors, aNames, localSize] := layoutExprList(ast.getAuditors())
            def newMethods := [].diverge()
            var frameNames := [].asSet()
            for m in (ast.getMethods()):
                def [newBody, mFreeNames, mls] := _layoutScopes(m.getBody())
                frameNames |= mFreeNames
                newMethods.push(builder.Method(
                    m.getDocstring(), m.getVerb(),
                    m.getParams(), m.getNamedParams(),
                    newBody, mls, m.getSpan()))
            def newMatchers := [].diverge()
            for m in (ast.getMatchers()):
                def [newBody, mFreeNames, mls] := _layoutScopes(m.getBody())
                frameNames |= mFreeNames
                newMatchers.push(builder.Matcher(
                    m.getPattern(), newBody, mls, m.getSpan()))
           return [builder.ObjectExpr(ast.getDocstring(), ast.getKernelAST(),
                                      newAuditors.snapshot(),
                                      newMethods.snapshot(),
                                      newMatchers.snapshot(),
                                      frameNames, ast.getSpan()),
                   aNames,
                   localSize]
       else if (nn == "NounExpr"):
           if (!accessTypes.contains(ast.getIndex())):
               accessTypes[ast.getIndex()] := NOUN
            return [builder.NounExpr(ast.getName(), ast.getIndex(), ast.getSpan()),
                    [ast.getIndex()].asSet(), 0]
       else if (nn == "BindingExpr"):
           accessTypes[ast.getIndex()] := BINDING
            return [builder.NounExpr(ast.getName(), ast.getIndex(), ast.getSpan()),
                    [ast.getIndex()].asSet(), 0]
       else if (nn == "IntExpr"):
           return [builder.IntExpr(ast.getI(), ast.getSpan()), [].asSet(), 0]
       else if (nn == "DoubleExpr"):
           return [builder.DoubleExpr(ast.getD(), ast.getSpan()), [].asSet(), 0]
       else if (nn == "CharExpr"):
           return [builder.CharExpr(ast.getC(), ast.getSpan()), [].asSet(), 0]
       else if (nn == "StrExpr"):
           return [builder.StrExpr(ast.getS(), ast.getSpan()), [].asSet(), 0]
       else if (nn == "NullExpr"):
           return [builder.NullExpr(ast.getSpan()), [].asSet(), 0]
       else if (nn == "MetaContextExpr"):
           return [builder.MetaContextExpr(ast.getSpan()), [].asSet(), 0]
       else if (nn == "MetaStateExpr"):
           return [builder.MetaContextExpr(ast.getSpan()), [].asSet(), 0]
       else if (nn == "CallExpr"):
           def [newRcvr, rFreeNames, rLocalSize] := _layoutScopes(ast.getReceiver())
           def [newArgs, aFreeNames, aLocalSize] := layoutExprList(ast.getArgs())
           def [newNArgs, nFreeNames, nLocalSize] := layoutExprList(ast.getNamedArgs())
           return [builder.CallExpr(newRcvr, ast.getVerb(), newArgs, newNArgs,
                                    ast.getSpan()),
                   rFreeNames | aFreeNames | nFreeNames,
                   rLocalSize.max(aLocalSize).max(nLocalSize)]
       else if (nn == "NamedArgExpr"):
           def [newK, kFreeNames, kLocalSize] := _layoutScopes(ast.getKey())
           def [newV, vFreeNames, vLocalSize] := _layoutScopes(ast.getValue())
           return [builder.NamedArgExpr(newK, newV, ast.getSpan()),
                   kFreeNames | vFreeNames,
                   kLocalSize.max(vLocalSize)]
       else if (nn == "TryExpr"):
           def [newBody, bFreeNames, bLocalSize] := _layoutScopes(ast.getBody())
           def [newCatchBody, cFreeNames, cLocalSize] := _layoutScopes(
               ast.getCatchBody())
           return [builder.TryExpr(newBody, ast.getCatchPattern(),
                                   newCatchBody, ast.getSpan()),
                   bFreeNames | cFreeNames,
                   bLocalSize.max(cLocalSize)]
       else if (nn == "FinallyExpr"):
           def [newBody, bFreeNames, bLocalSize] := _layoutScopes(ast.getBody())
           def [newUnwinder, uFreeNames, uLocalSize] := _layoutScopes(
               ast.getUnwinder())
           return [builder.FinallyExpr(newBody, newUnwinder, ast.getSpan()),
                   bFreeNames | uFreeNames,
                   bLocalSize.max(uLocalSize)]
       else if (nn == "EscapeExpr"):
           def [newBody, bFreeNames, bLocalSize] := _layoutScopes(ast.getBody())
           def [newCatchBody, cFreeNames, cLocalSize] := _layoutScopes(
               ast.getCatchBody())
           return [builder.EscapeExpr(ast.getEjectorPattern(), newBody,
                                      ast.getCatchPattern(), newCatchBody,
                                      ast.getSpan()),
                   bFreeNames | cFreeNames,
                   bLocalSize.max(cLocalSize)]
       else if (nn == "EscapeOnlyExpr"):
           def [newBody, bFreeNames, bLocalSize] := _layoutScopes(ast.getBody())
           return [builder.EscapeOnlyExpr(ast.getEjectorPattern(), newBody,
                                      ast.getSpan()),
                   bFreeNames,
                   bLocalSize]
       else if (nn == "IfExpr"):
           def [newTest, tFreeNames, tLocalSize] := _layoutScopes(ast.getTest())
           def [newConsq, cFreeNames, cLocalSize] := _layoutScopes(ast.getThen())
           def [newAlt, aFreeNames, aLocalSize] := _layoutScopes(ast.getElse())
           return [builder.IfExpr(newTest, newConsq, newAlt, ast.getSpan()),
                   tFreeNames | cFreeNames | aFreeNames,
                   tLocalSize.max(cLocalSize).max(aLocalSize)]
       else if (nn == "GuardCoerce"):
           def [newSpecimen, sFreeNames, sLocalSize] := _layoutScopes(
               ast.getSpecimen())
           def [newGuard, gFreeNames, gLocalSize] := _layoutScopes(ast.getGuard())
           def [newExit, eFreeNames, eLocalSize] := _layoutScopes(ast.getExit())
           return [builder.GuardCoerce(newSpecimen, newGuard, newExit, ast.getSpan()),
                   sFreeNames | gFreeNames | eFreeNames,
                   sLocalSize.max(gLocalSize).max(eLocalSize)]
       else if (nn == "ListCoerce"):
           def [newSpecimen, sFreeNames, sLocalSize] := _layoutScopes(
               ast.getSpecimen())
           def [newExit, eFreeNames, eLocalSize] := _layoutScopes(ast.getExit())
           return [builder.GuardCoerce(newSpecimen, ast.getSize(), newExit,
                                       ast.getSpan()),
                   sFreeNames | eFreeNames,
                   sLocalSize.max(eLocalSize)]
       else if (nn == "NamedParamExtract"):
           def [newParams, pFreeNames, pLocalSize] := _layoutScopes(
               ast.getParams())
           def [newKey, kFreeNames, kLocalSize] := _layoutScopes(ast.getKey())
           def [newDefault, dFreeNames, dLocalSize] := _layoutScopes(ast.getDefault())
           return [builder.NamedParamExtract(newParams, newKey, newDefault,
                                             ast.getSpan()),
                   pFreeNames | kFreeNames | dFreeNames,
                   pLocalSize.max(kLocalSize).max(dLocalSize)]

    def [expr, freeNames, localSize] := _layoutScopes(ast)


#AssignExpr -> slot.put()
#lay out frames, rewrite nouns
#expand MetaStateExpr
#----------------------
#Expand MetaContextExpr
#elide trivial 'return'
#replace CallExpr verbs with atoms

"
Layout plan:
LetDef gains originalName
LetDef name becomes index
Global list of definitions built
Global list of noun severity built
Walk AST building frames for objects

"
