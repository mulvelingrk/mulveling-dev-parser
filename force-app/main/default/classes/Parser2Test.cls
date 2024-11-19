@isTest
private class Parser2Test {
    static final Boolean StrictMode = true;
    static final Boolean UnstrictMode = false;
    
    static Boolean DefaultMode = UnstrictMode;
    
    /*
    static Integer parseExprInstrucs(CodeContext.GlobalCode hostCode, String strExpr) {
        try {
            Lexer2 lex = Lexer2.newLexer(null, strExpr);
            return Parser2.parseExpr(lex, hostCode, hostCode.instrucs, Parser2.LVL_COMMA, false, Parser2.TOVAL_RESULT, null);
        } catch (ParseException e) {
            System.assert(false, 'ParseError: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
        return null;
    }
    
    static void verifyExprInstrucs(String strExpr, Integer expectedLvl, String expectedInstrucs) {
        CodeContext.GlobalCode module = new CodeContext.GlobalCode(false);
        module.strict = DefaultMode;
        Integer exprReturn = parseExprInstrucs(module, strExpr);
        Integer exprLvl = exprReturn & Parser2.EXPR_LVL_MASK;
        System.assertEquals(expectedLvl, exprLvl);
        System.assertEquals(expectedInstrucs, Instruc.toString(module.instrucs));
    }
    
    static CodeContext.GlobalCode verifyModuleInstrucs(String globalCode, String expectedInstrucs) {
        return verifyModuleInstrucs(globalCode, null, expectedInstrucs);
    }
    
    static CodeContext.GlobalCode verifyModuleInstrucs(String globalCode, Boolean strict, String expectedInstrucs) {
        CodeContext.GlobalCode module;
        try {
            module = Parser2.parseGlobalCode(new Context(), '<test>', globalCode, strict == null ? DefaultMode : strict);
        } catch (ParseException e) {
            System.assert(false, 'ParseError: ' + e.getMessage());
        }
        System.assert(expectedInstrucs == Instruc.toString(module.instrucs), 'Unexpected result [' + 
                module.instrucs.size() + ' instrucs]: ' + Instruc.toString(module.instrucs));
        return module;
    }
    
    static void verifyModuleParse(String globalCode) {
        verifyModuleParse(globalCode, null);
    }
    
    static void verifyModuleParse(String globalCode, Boolean strict) {
        try {
            Parser2.parseGlobalCode(new Context(), '<test>', globalCode, strict == null ? DefaultMode : strict);
        } catch (ParseException e) {
            System.assert(false, 'Unexpected parse error [at ' + (e.loc.line + 1) + ', ' + (e.loc.col + 1) + ']: ' + e.getMessage());
        }
    }
    
    static void verifyModuleError(String globalCode, String expectedMsgPart) {
        verifyModuleError(globalCode, null, expectedMsgPart, null, null);
    }
    
    static void verifyModuleError(String globalCode, Boolean strict, String expectedMsgPart) {
        verifyModuleError(globalCode, strict, expectedMsgPart, null, null);
    }
    
    static void verifyModuleError(String globalCode, String expectedMsgPart, Integer line, Integer col) {
        verifyModuleError(globalCode, null, expectedMsgPart, line, col);
    }
    
    static void verifyModuleError(String globalCode, Boolean strict, String expectedMsgPart, Integer line, Integer col) {
        CodeContext.GlobalCode module;
        ParseException pe;
        try {
            module = Parser2.parseGlobalCode(new Context(), '<test>', globalCode, strict == null ? DefaultMode : strict);
        } catch (ParseException e) {
            pe = e;
        }
        System.assert(pe != null, 'Expected parse error');
        if (expectedMsgPart != null)
            System.assert(Pattern.compile('(?i)' + expectedMsgPart).matcher(pe.getMessage()).find(), 'Expected a different ParseError, got: ' + pe.getMessage());
        
        if (line != null) {
            System.assert(line == pe.loc.line + 1, 'Expected error occurred at line ' 
                    + (pe.loc.line + 1) + ' instead of the expected line ' + line);
            if (col != null)
                System.assert(col == pe.loc.col + 1, 'Expected error occurred at line ' + (pe.loc.line + 1) 
                        + ', col ' + (pe.loc.col + 1) + ' instead of the expected col ' + col);
        }
    }
    
    static Instruc[] verifyFuncExpr(Instruc funcExpr, Boolean expectedStrict, String expectedSegmentInstrucs) {
        System.assert(funcExpr instanceof Instruc.FunctionExpr, 'Expected a FunctionExpr instruction');
        return verifyFuncCode((CodeContext.Function) funcExpr.objVal, expectedStrict, expectedSegmentInstrucs);
    }
    
    static Instruc[] verifyGetter(Instruc objGetter, Boolean expectedStrict, String expectedSegmentInstrucs) {
        System.assert(objGetter instanceof Instruc.ObjectLitGetter, 'Expected a ObjectLitGetter instruction');
        return verifyFuncCode((CodeContext.Function) ((Instruc.ObjectLitGetter) objGetter).objVal, expectedStrict, expectedSegmentInstrucs);
    }
    
    static Instruc[] verifySetter(Instruc objSetter, Boolean expectedStrict, String expectedSegmentInstrucs) {
        System.assert(objSetter instanceof Instruc.ObjectLitSetter, 'Expected a ObjectLitSetter instruction');
        return verifyFuncCode((CodeContext.Function) ((Instruc.ObjectLitSetter) objSetter).objVal, expectedStrict, expectedSegmentInstrucs);
    }
    
    static Instruc[] verifyFuncCode(CodeContext.Function funcCode, Boolean expectedStrict, String expectedSegmentInstrucs) {
        System.assert(expectedStrict == funcCode.strict, 'Expected function code to be ' + (expectedStrict ? 'strict' : 'non-strict'));
        System.assert(expectedSegmentInstrucs == Instruc.toString(funcCode.instrucs), 'Unexpected function expression instructions [' + 
                funcCode.instrucs.size() + ' instrucs]: ' + Instruc.toString(funcCode.instrucs));
        return funcCode.instrucs;
    }
    
    @isTest 
    static void testExpr1() {
        // very simple arith expr:
        verifyExprInstrucs('x + y * 2', Parser2.LVL_ARITH,
                'PUSH[x] VAL PUSH[y] VAL PUSH[2.0] * +');
        
        // two consecutive new-ops, both with member accessors, but with only the 1st binding to explicit call-args; short-circuting || op, and comma-op:
        verifyExprInstrucs('(new new x.foo(y, z)\n    .bar[1 + 1] + 42) * 2, baz || qux', Parser2.LVL_COMMA,
                'PUSH[x] VAL PROP[foo] VAL ARGS_START PUSH[y] VAL ARGS_ADD PUSH[z] VAL ARGS_ADD CONSTRUCT PROP[bar] VAL PUSH[1.0] PUSH[1.0] + SUBSCRIPT VAL ARGS_START CONSTRUCT PUSH[42.0] + PUSH[2.0] * PUSH[baz] VAL JMPT[31] POP PUSH[qux] VAL POP_PEN');
        
        // the 2nd call-args should raise the new-expr to a call-expr:
        verifyExprInstrucs('new x.foo(y, z)()', Parser2.LVL_CALL,
                'PUSH[x] VAL PROP[foo] VAL ARGS_START PUSH[y] VAL ARGS_ADD PUSH[z] VAL ARGS_ADD CONSTRUCT COPY ARGS_START CALL VAL');
        
        // unary:
        verifyExprInstrucs('+-foo', Parser2.LVL_UNARY,
                'PUSH[foo] VAL u- u+');
        
        // consecutive unary ops, ternary, chained assignments with a compound assignment-op:
        verifyExprInstrucs('typeof !! delete foo * 2 ? baz : qux = quux += corge', Parser2.LVL_TERNARY,
                'PUSH[foo] delete ! ! typeof PUSH[2.0] * JMPF[POP][11] PUSH[baz] VAL GOTO[19] PUSH[qux] PUSH[quux] PUSH[corge] VAL COPY_PEN[VAL] + PUT[1] PUT[1]');
        
        // nested ternary ops:
        verifyExprInstrucs('foo ? bar ? baz ? qux + 1 : quux = corge : grault : garply', Parser2.LVL_TERNARY,
            'PUSH[foo] VAL JMPF[POP][22] PUSH[bar] VAL JMPF[POP][19] PUSH[baz] VAL JMPF[POP][14] PUSH[qux] VAL PUSH[1.0] + GOTO[18] PUSH[quux] PUSH[corge] VAL PUT[1] GOTO[21] PUSH[grault] VAL GOTO[24] PUSH[garply] VAL');
        
        // logical-or:
        verifyExprInstrucs('foo || bar || baz', Parser2.LVL_LOGICALOR, 
                'PUSH[foo] VAL JMPT[10] POP PUSH[bar] VAL JMPT[10] POP PUSH[baz] VAL');
        
        // logical-and:
        verifyExprInstrucs('foo && bar && baz', Parser2.LVL_LOGICALAND, 
                'PUSH[foo] VAL JMPF[10] POP PUSH[bar] VAL JMPF[10] POP PUSH[baz] VAL');
        
        // resolve '/' ambiguity (to a divide op, in this case) via parser feedback:
        verifyExprInstrucs('foo++ / bar', Parser2.LVL_MULT, 
                'PUSH[foo] ++ PUSH[bar] VAL /');
        
        // resolve '/' ambiguity (to a regexp, in this case) via parser feedback to the lexer:
        verifyExprInstrucs('++/foo/idmsuxg[1]', Parser2.LVL_UNARY, 
                'PUSH[<regexp[(?idmsux)foo][idmsuxg]>] PUSH[1.0] SUBSCRIPT ++');
        
        verifyExprInstrucs('x[y[z]]', Parser2.LVL_CALL,
                'PUSH[x] VAL PUSH[y] VAL PUSH[z] VAL SUBSCRIPT VAL SUBSCRIPT VAL');
    }
    
    @isTest
    static void testSyntaxErrors() {
        DefaultMode = UnstrictMode;
        
        // don't allow a property access to follow a postfix operator:
        verifyModuleError('var foo;\nfoo++.bar', '^Unexpected token.+property access', 2, 6);
        verifyModuleError('foo++\n["bar"]', '^Unexpected token.+property access', 2, 1);
        // don't allow call arguments to follow a postfix operator:
        verifyModuleError('foo++(bar,baz)', '^Unexpected token.+call arguments', 1, 6);
        // do allow a postfix to follow call arguments or property access:
        verifyModuleParse('foo(bar,baz)++;\nfoo.bar++;\nfoo["bar"]++');
        
        DefaultMode = StrictMode;
        
        // in strict mode, don't allow a direct (environment) assignment into eval or arguments:
        verifyModuleError('eval = 42;', '^Assignment to eval', 1, 6);
        verifyModuleError('arguments=42;', '^Assignment to arguments', 1, 10);
        // do allow these same things when not in strict mode:
        verifyModuleParse('eval=42;arguments=42', UnstrictMode);
        // do allow assignments into properties named eval or arguments, even in strict mode:
        verifyModuleParse('foo.eval=42;bar.arguments=42');
        
        // in strict mode, don't allow a postfix ++/-- on a direct environment reference to eval/arguments:
        
        verifyModuleError('1 + eval++', '^Postfix \'\\+\\+\' on eval', 1, 9);
        verifyModuleError('1 + (eval)++', '^Postfix \'\\+\\+\' on eval', 1, 11);
        verifyModuleError('1 + (((eval)))++', '^Postfix \'\\+\\+\' on eval', 1, 15);
        
        verifyModuleError('1 + arguments--', '^Postfix \'\\-\\-\' on arguments', 1, 14);
        verifyModuleError('1 + (arguments)--', '^Postfix \'\\-\\-\' on arguments', 1, 16);
        verifyModuleError('1 + (((arguments)))--', '^Postfix \'\\-\\-\' on arguments', 1, 20);
        
        verifyModuleParse('1 + eval.foo++');
        verifyModuleParse('1 + (eval).foo++');
        verifyModuleParse('1 + (eval.foo)++');
        verifyModuleParse('1 + eval++', UnstrictMode);
        
        verifyModuleParse('1 + arguments.foo--');
        verifyModuleParse('1 + (arguments).foo--');
        verifyModuleParse('1 + (arguments.foo)--');
        verifyModuleParse('1 + arguments--', UnstrictMode);
        
        // in strict mode, don't allow a prefix ++/-- on a direct environment reference to eval/arguments:
        
        verifyModuleError('1 + ++eval', '^Prefix \'\\+\\+\' on eval', 1, 5);
        verifyModuleError('1 + ++(eval)', '^Prefix \'\\+\\+\' on eval', 1, 5);
        verifyModuleError('1 + ++(( ( eval ) ))', '^Prefix \'\\+\\+\' on eval', 1, 5);
        
        verifyModuleError('1 + --arguments', '^Prefix \'\\-\\-\' on arguments', 1, 5);
        verifyModuleError('1 + --(arguments)', '^Prefix \'\\-\\-\' on arguments', 1, 5);
        verifyModuleError('1 + --(( ( arguments ) ))', '^Prefix \'\\-\\-\' on arguments', 1, 5);
        
        verifyModuleParse('1 + ++eval.foo');
        verifyModuleParse('1 + ++(eval).foo');
        verifyModuleParse('1 + ++(eval.foo)');
        verifyModuleParse('1 + ++eval', UnstrictMode);
        
        verifyModuleParse('1 + --arguments.foo');
        verifyModuleParse('1 + --(arguments).foo');
        verifyModuleParse('1 + --(arguments.foo)');
//        verifyModuleParse('1 + --(new (arguments))', UnstrictMode);
        verifyModuleError('1 + --(new (arguments))', UnstrictMode, '^Invalid right\\-hand side for prefix \'\\-\\-\'', 1, 5);
        
        // the application of 'new' to eval or arguments bypasses the above referenced SyntaxError checks -- even in cases where the 'new' op is
        // applied through ()'s groupings. however, note that running the following code should yield the appropriate TypeErrors, since eval and
        // arguments are not constructors:
        //verifyModuleError('1 + new eval++', UnstrictMode, '^Invalid left\\-hand side for postfix \'\\+\\+\'', 1, 13);
//        verifyModuleParse('1 + new eval++');
//        verifyModuleParse('1 + --new arguments');
//        verifyModuleParse('1 + --(new arguments)');
//        verifyModuleParse('1 + --(new (arguments))');
//        verifyModuleParse('1 + ((new ((eval)))++)');
//        // ...and now with explicit call args bound to each new op:
//        verifyModuleParse('1 + new eval()++');
//        verifyModuleParse('1 + --new arguments()');
//        verifyModuleParse('1 + --(new eval())');
//        // ...and with multiple new ops:
//        verifyModuleParse('1 + new new eval()()++');
//        verifyModuleParse('1 + new new eval()++');
//        verifyModuleParse('1 + --new new arguments()()');
//        verifyModuleParse('1 + ++new new arguments');
        
        // the application of a call invocation (non-constructor call) to eval or arguments bypasses the SyntaxError checks in a similar fashion as
        // to the 'new' op (see above):
        verifyModuleParse('1 + --arguments()');
        verifyModuleParse('1 + --(arguments())');
        verifyModuleParse('1 + eval()++');
        
//        verifyExprInstrucs('1 + new new eval()++', Parser2.LVL_ARITH, 
//            'PUSH[1.0] PUSH[eval] VAL ARGS_START CONSTRUCT ARGS_START CONSTRUCT ++ +');
        
        // test special strict-mode restrictions on 'delete':
        verifyModuleParse('delete foo.bar');
        verifyModuleParse('delete foo()');
        verifyModuleParse('delete foo++');
        verifyModuleParse('delete ++foo');
        verifyModuleParse('delete (foo)++');
        verifyModuleParse('delete {}');
        verifyModuleParse('delete function(){}');
        verifyModuleParse(
            'delete foo.bar\n' + 
            'delete foo()\n' + 
            'delete foo++;\n' + 
            'delete ++foo;\n' + 
            'delete (foo)++\n' + 
            'delete {}\n' + 
            'delete function(){}');
        
        verifyModuleError('delete foo', '^Delete of unqualified reference \'foo\'', 1, 1);
        verifyModuleError('delete ((foo))', '^Delete of unqualified reference \'foo\'', 1, 1);
        verifyModuleError('delete eval', '^Delete of unqualified reference \'eval\'', 1, 1);
        DefaultMode = UnstrictMode;
        verifyModuleParse('delete foo');
        verifyModuleParse('delete (foo)');
    }
    
    @isTest 
    static void testLoops() {
        String code = 
            'var x=0, y=0, z=10;\n' + 
            'while (x + y > z) {\n' + 
            '    x++;\n' + 
            '    y++;\n' + 
            '}';
        verifyModuleInstrucs(code, false, 'PUSH[x] PUSH[0.0] PUT PUSH[y] PUSH[0.0] PUT PUSH[z] PUSH[10.0] PUT POP[6] PUSH[x] VAL PUSH[y] VAL + PUSH[z] VAL > JMPF[POP][26] PUSH[x] ++ RESULT PUSH[y] ++ RESULT GOTO[10] END');
        
        code = 
            'for (foo[i * 2][j] in bar.baz)\n' + 
            '    for (var k in qux)\n' + 
            '        for (var x=0; x < 100; x++, y++)\n' + 
            '            console.log("test");';
        verifyModuleInstrucs(code, false, 
                'PUSH[bar] VAL PROP[baz] VAL ENUM_START ENUM_NEXT[52] PUSH[foo] VAL PUSH[i] VAL PUSH[2.0] * SUBSCRIPT VAL PUSH[j] VAL SUBSCRIPT PUT[REV][2] PUSH[qux] VAL ENUM_START ' + 
                    'ENUM_NEXT[51] PUSH[k] PUT[REV][2] PUSH[x] PUSH[0.0] PUT POP[2] ' + 
                        'PUSH[x] VAL PUSH[100.0] < JMPF[POP][50] PUSH[console] VAL PROP[log] COPY[VAL] ARGS_START PUSH["test"] ARGS_ADD CALL VAL RESULT PUSH[x] ++ PUSH[y] ++ POP_PEN POP GOTO[28] GOTO[21] GOTO[5] END');
        
        code = 
            'outer: \n' + 
            'for (i=0; i < 10; i++)\n' + 
            '    for (j=0; j < 10; j++) {\n' + 
            '        if (i <= 5 && j == 5)\n' + 
            '            continue outer\n' + 
            '        else if (i > 5 && j === 5) {\n' + 
            '            break outer\n' + 
            '        }\n' + 
            '        continue;\n' + 
            '    }\n';
        verifyModuleInstrucs(code, false, 
                'PUSH[i] PUSH[0.0] PUT[1] POP PUSH[i] VAL PUSH[10.0] < JMPF[POP][53] PUSH[j] PUSH[0.0] PUT[1] POP ' + 
                    'PUSH[j] VAL PUSH[10.0] < JMPF[POP][49] PUSH[i] VAL PUSH[5.0] <= JMPF[28] POP PUSH[j] VAL PUSH[5.0] == JMPF[POP][31] CONTINUE[49][outer] GOTO[44] PUSH[i] VAL PUSH[5.0] > JMPF[41] POP PUSH[j] VAL PUSH[5.0] === JMPF[POP][44] BREAK[53][outer] GOTO[44] CONTINUE[45] PUSH[j] ++ POP GOTO[13] PUSH[i] ++ POP GOTO[4] END');
        
        code = 
            'for (var i, j in qux) ;';
        verifyModuleError(code, false, 'may only declare a single variable', 1, 15);
        
        code = 
            'foo ? bar ? baz : qux';
        verifyModuleError(code, false, 'to continue ternary operator.+unexpected end-of-file', 1, 22);
    }
    
    @isTest
    static void testFunctions() {
        CodeContext.GlobalCode module;
        Instruc[] instrucs;
        String code = 
            'function foo (x, y, x) {\n' + 
            '    "use strict"\n' + 
            '}';
        verifyModuleError(code, false, '\'x\' may not be duplicated in strict mode function \'foo\'', 1, 21);
        
        code = 
            'function eval (x, y, z) {\n' + 
            '    "use strict"\n' + 
            '}';
        verifyModuleError(code, false, 'name \'eval\' may not be used for a strict mode function', 1, 10);
        
        code = 
            'function Foo (x) {\n' + 
            '    "use strict"\n' +
            '    return x * x }';
        module = verifyModuleInstrucs(code, false, 'END');
        instrucs = verifyFuncCode(module.functionDecs[0], true, 'PUSH["use strict"] POP PUSH[x] VAL PUSH[x] VAL * RETURN END');
        
        code = 
            'var foo = function bar (a) {\n' + 
            '    console.log(a)\n' + 
            '    return function (x, y, z) {\n' + 
            '        "use strict"\n' + 
            '        return x + y + z\n' + 
            '    }\n' + 
            '}("testing")';
        module = verifyModuleInstrucs(code, false, 'PUSH[foo] PUSH[<function[bar]>] COPY ARGS_START PUSH["testing"] ARGS_ADD CALL VAL PUT POP[2] END');
        instrucs = module.instrucs;
        instrucs = verifyFuncExpr(instrucs[1], false, 'PUSH[console] VAL PROP[log] COPY[VAL] ARGS_START PUSH[a] VAL ARGS_ADD CALL VAL POP PUSH[<function[null]>] RETURN END');
        instrucs = verifyFuncExpr(instrucs[11], true, 'PUSH["use strict"] POP PUSH[x] VAL PUSH[y] VAL + PUSH[z] VAL + RETURN END');
    }
    
    @isTest
    static void testFunctionTraceName() {
        CodeContext.GlobalCode module;
        Instruc[] instrucs;
        String code = 
            'foo.bar = { baz: { qux: function () {} } }';
        module = verifyModuleInstrucs(code, false, 
            'PUSH[foo] VAL PROP[bar] OBJ_START OBJ_START PUSH[<function[null]>] OBJ_PROP[qux] OBJ_PROP[baz] PUT[1] RESULT END');
        System.assertEquals('Object.foo.bar.baz.qux', ((CodeContext.Function) module.instrucs[5].objVal).getTraceName(null));
        
        // an anonymous function can inherit a var declaration's identifier name:
        code = 
            'var foobar = function () {}';
        module = verifyModuleInstrucs(code, false, 
            'PUSH[foobar] PUSH[<function[null]>] PUT POP[2] END');
        System.assertEquals('foobar', ((CodeContext.Function) module.instrucs[1].objVal).getTraceName(null));
        
        // in an assignment chain, a righthand anonymous function only inherits the reference-chain of the last assignee (i.e. the function's
        // immediate lefthand):
        code = 
            'foo.bar = baz.qux = function () {}';
        module = verifyModuleInstrucs(code, false, 
            'PUSH[foo] VAL PROP[bar] PUSH[baz] VAL PROP[qux] PUSH[<function[null]>] PUT[1] PUT[1] RESULT END');
        System.assertEquals('Object.baz.qux', ((CodeContext.Function) module.instrucs[6].objVal).getTraceName(null));
        
        // the "prototype" property name is filtered out from an anonymous function's inferred name:
        code = 
            'Foo.prototype = { "bar": function () {} }';
        module = verifyModuleInstrucs(code, false, 
            'PUSH[Foo] VAL PROP[prototype] OBJ_START PUSH[<function[null]>] OBJ_PROP[bar] PUT[1] RESULT END');
        System.assertEquals('Object.Foo.bar', ((CodeContext.Function) module.instrucs[4].objVal).getTraceName(null));
        
        // subscripts will be compiled into property names where possible:
        code = 
            'foo["bar"][0xff] = { "baz": function () {} }';
        module = verifyModuleInstrucs(code, false, 
            'PUSH[foo] VAL PUSH["bar"] SUBSCRIPT VAL PUSH[255.0] SUBSCRIPT OBJ_START PUSH[<function[null]>] OBJ_PROP[baz] PUT[1] RESULT END');
        System.assertEquals('Object.foo.bar.255.baz', ((CodeContext.Function) module.instrucs[8].objVal).getTraceName(null));
        
        // when subscripts cannot be compiled into property names, we will use the token "<dynamic>":
        code = 
            'foo["bar"][2 + 2] = { "baz": function () {} }';
        module = verifyModuleInstrucs(code, false, 
            'PUSH[foo] VAL PUSH["bar"] SUBSCRIPT VAL PUSH[2.0] PUSH[2.0] + SUBSCRIPT OBJ_START PUSH[<function[null]>] OBJ_PROP[baz] PUT[1] RESULT END');
        System.assertEquals('Object.foo.bar.<dynamic>.baz', ((CodeContext.Function) module.instrucs[10].objVal).getTraceName(null));
        
        // a call invocation resets the lefthandRefChain to a single-element list of "[[Call]]":
        code = 
            'garply.foo().bar.baz = { qux: function () {} }';
        module = verifyModuleInstrucs(code, false, 
            'PUSH[garply] VAL PROP[foo] COPY[VAL] ARGS_START CALL VAL PROP[bar] VAL PROP[baz] OBJ_START PUSH[<function[null]>] OBJ_PROP[qux] PUT[1] RESULT END');
        System.assertEquals('[[Call]].bar.baz.qux', ((CodeContext.Function) module.instrucs[11].objVal).getTraceName(null));
        
        // a new-op (i.e. constructor invocation) also resets the lefthandRefChain to a single-element list of "[[Call]]":
        code = 
            '(new foo).bar.baz = { qux: function () {} }';
        module = verifyModuleInstrucs(code, false, 
            'PUSH[foo] VAL ARGS_START CONSTRUCT PROP[bar] VAL PROP[baz] OBJ_START PUSH[<function[null]>] OBJ_PROP[qux] PUT[1] RESULT END');
        System.assertEquals('[[Construct]].bar.baz.qux', ((CodeContext.Function) module.instrucs[8].objVal).getTraceName(null));
    }
    
    @isTest
    static void testAccessors() {
        CodeContext.GlobalCode module;
        Instruc[] instrucs;
        String code = 
            'var foo = [{\n' + 
            '    corge: "corge",\n' + 
            '    get bar () {\n' + 
            '        return this._bar;\n' + 
            '    },\n' + 
            '    set bar (bar) {\n' + 
            '        this._bar = bar;\n' + 
            '    },\n' + 
            '    baz: "baz",\n' + 
            '},, 42, ]\n';
        module = verifyModuleInstrucs(code, false, 'PUSH[foo] ARRAY_START OBJ_START PUSH["corge"] OBJ_PROP[corge] OBJ_GETTER[bar] OBJ_SETTER[bar] PUSH["baz"] OBJ_PROP[baz] ARRAY_ADD PUSH[<elision>] ARRAY_ADD PUSH[42.0] ARRAY_ADD ARRAY_END PUT POP[2] END');
        instrucs = module.instrucs;
        verifyGetter(instrucs[5], false, 'PUSH[this] PROP[_bar] VAL RETURN END');
        verifySetter(instrucs[6], false, 'PUSH[this] PROP[_bar] PUSH[bar] VAL PUT[1] POP END');
    }
    */
}