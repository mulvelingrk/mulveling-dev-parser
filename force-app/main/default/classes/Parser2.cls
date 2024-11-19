/*
 * Mike Ulveling
 * 
 * You don't understand. I don't think you understand, truly, how much I enjoy writing parsing code. Even in as backwoods a language as Apex.
 * 
 * TODO: 
 * Throw error for invalid regexpFlags when instantiating RegExp literal
 */
public class Parser2 {
    static final Boolean ALLOW_IN_OP = false;
    static final Boolean NO_IN_OP = true;

    // there are no distinguishing factors among instances of POP, and they cannot cause a runtime exception to be thrown, so we reuse a single
    // instance repeatedly:
    static final Instruc POP = new Instruc.Pop();
    static final Instruc POPPEN = new Instruc.PopPen();
    static final Instruc SWP = new Instruc.Swap();
    static final Instruc CPY = new Instruc.Copy();
    static final Instruc CPYPEN = new Instruc.CopyPen();
    static final Instruc FORK = new Instruc.ForkTop();
    static final Instruc PUSH_UNDEFINED = new Instruc.Push(null);
    static final Instruc PUSH_STR_UNDEF = new Instruc.Push('undefined');
    static final Instruc INC1 = new Instruc.Inc(1);
    static final Instruc DEC1 = new Instruc.Inc(-1);
    static final Instruc RESULT = new Instruc.Result();
    public static final Instruc RET_RES = new Instruc.ReturnResult();
    public static final Instruc RET_NONE = new Instruc.ReturnNone();
    public static final Instruc RET_TOP = new Instruc.ReturnTop();
    public static final Instruc RET_DEF = new Instruc.ReturnDefault();
    public static final Instruc RET_EXP = new Instruc.ReturnExpr();
    
    // some unary operations may flag their operand as the penultimate slot rather than the top slot (the latter being default):
    public static final Boolean TOP_OP = Instruc.TOP_OP;
    public static final Boolean PEN_OP = Instruc.PEN_OP;

    // some of the type preprocessing instructions may use 2 passes (e.g. ToNum, ToInt32):
    public static final Integer ONE_PASS = Instruc.ONE_PASS;
    public static final Integer PASS_A = Instruc.PASS_A;
    public static final Integer PASS_B = Instruc.PASS_B;
    
    // hint flags for the ToPrim instruc:
//    public static final Boolean NO_HINT = Instruc.NO_HINT;
//    public static final Boolean STR_HINT = Instruc.STR_HINT;
//    public static final Boolean NUM_HINT = Instruc.NUM_HINT;
    public static final Integer NO_HINT = 0;
    public static final Integer STR_HINT = 0;
    public static final Integer NUM_HINT = 0;
    
    // the following ToInt32/ToUint32/ToNum/ToStr/ToBool instances don't need to be unique (i.e. don't need token loc) because they cannot dispatch
    // [[DefaultValue]] and cannot yield side-effects (only pass A instances can do so):
    public static Instruc INT32_B = new Instruc.ToInt32(null, PASS_B, TOP_OP);
    public static Instruc INT32_TOP = new Instruc.ToInt32(null, ONE_PASS, TOP_OP);
    public static Instruc INT32_PEN = new Instruc.ToInt32(null, ONE_PASS, PEN_OP);
    public static Instruc UINT32_B = new Instruc.ToUint32(null, PASS_B, TOP_OP);
    public static Instruc UINT32_TOP = new Instruc.ToUint32(null, ONE_PASS, TOP_OP);
    public static Instruc UINT32_PEN = new Instruc.ToUInt32(null, ONE_PASS, PEN_OP);
    public static Instruc NUM_B = new Instruc.ToNum(null, PASS_B, TOP_OP);
    public static Instruc NUM_TOP = new Instruc.ToNum(null, ONE_PASS, TOP_OP);
    public static Instruc NUM_PEN = new Instruc.ToNum(null, ONE_PASS, PEN_OP);
    public static Instruc BOOL_B = new Instruc.ToBool(null, PASS_B, TOP_OP);
    public static Instruc BOOL_TOP = new Instruc.ToBool(null, ONE_PASS, TOP_OP);
    public static Instruc STR_B = new Instruc.ToStr(null, PASS_B, TOP_OP);
    public static Instruc STR_TOP = new Instruc.ToStr(null, ONE_PASS, TOP_OP);
    
    public static Instruc BTOR = new Instruc.BitOr();
    public static Instruc BTXOR = new Instruc.BitXor();
    public static Instruc BTAND = new Instruc.BitAnd();
    
    public static Instruc LSHFT = new Instruc.LeftShift();
    public static Instruc RSHFT = new Instruc.RightShift();
    public static Instruc URSHFT = new Instruc.URightShift();
    
    public static Instruc MULTIPLY = new Instruc.Multiply();
    public static Instruc DIVIDE = new Instruc.Divide();
    public static Instruc MODULUS = new Instruc.Modulus();
    
    public static Instruc ADD = new Instruc.Add();
    public static Instruc SUBTRACT = new Instruc.Subtract();
    
    public static Instruc ARGVSTART = new Instruc.ArgStart();
    public static Instruc ARGVADD = new Instruc.ArgAdd();
    
    public static Instruc JMPREFOK4 = new Instruc.JumpIfRefResolved(4);
    public static Instruc JMP4 = new Instruc.Jump(4);
    public static Instruc TYPEOF = new Instruc.TypeOf();
    public static Instruc LOGICAL_NOT = new Instruc.LogicalNot();
    public static Instruc BIT_NOT = new Instruc.BitNot();
    public static Instruc NUM_NEGATE = new Instruc.NumNegate();
    
    // parses a hexadecimal integer number (the "0x" prefix must be stripped) into an IEEE 64-bit double; note that we will eventually lose precision
    // as dictated by the limitations of double-precision, but this is as per the ECMAScript specification: 
    public static Double parseHex(String digits) {
        Double val = 0;
        for (Integer i=0; i < digits.length(); i++) {
            val *= 16;
            val += Lexer2.HexadecimalDigits.indexOfIgnoreCase(digits.mid(i, 1));
        }
        return val;
    }
    
    // all integers of this magnitude or smaller are guaranteed to be precisely represented (without loss) by an IEEE 64-bit double (as used in Apex
    // and Java); this value is smaller than the maximum 64-bit integer, but larger than the maximum 32-bit integer:
    public static Double DBL_PRECISE_INT_MAX = Math.pow(2, 53);
    
    // see ECMAScript5 9.8.1
    public static String toString(Double num) {
        // handle NaN and Infinity:
        if (num == Utils.NaN || num == Utils.Infinity || num == Utils.MinusInfinity)
            return String.valueOf(num);
        // handle +0 and -0:
        else if (num == 0 || num == Utils.MinusZero)
            return '0';
        // handle integer values -- in the range that can be precisely represented by double precision -- by deferring to Long.toString() (it should
        // be more efficient than the subsequent logic):
        else if (num.longValue() == num && num <= DBL_PRECISE_INT_MAX && num >= -DBL_PRECISE_INT_MAX)
            return String.valueOf(num.longValue());
        
        String m = String.valueOf(num); // the host system's Double.toString (Apex defers to a standard Java lib, I trust, or else it will be completely fucked)
        String s;
        Integer expIndex = m.indexOf('E');
        // if we have an exponent, then we can assume the rigid output format of Java's Double.toString (which Apex defers to), and therefore more
        // easily slice up the result to derive ECMAScript5 9.8.1's 's', 'n', and 'k' values:
        if (expIndex > 0) {
            s = m.substring(0, expIndex);
            Integer exp;
            if (m.mid(expIndex + 1, 1) == '-')
                exp = -Integer.valueOf(m.substring(expIndex + 2, m.length()));
            else
                exp = Integer.valueOf(m.substring(expIndex + 1, m.length()));
            
            // remove the decimal and (when found) a non-significant trailing 0:
            if (s.endsWith('.0'))
                s = s.substring(0, s.length() - 2);
            else
                s = s.replace('.', '');
            
            // k = s.length(); n = exp + 1
            return numToString(s, exp + 1);
            
        // else, no exponent, but we must have a non-integer value, as we've already handled ints above:
        } else {
            // e.g. 0.00000132764274687 => startsWith '0.'; we can count on not having trailing zeros (Double.toString will not output them in this
            // scenario); in this example, we derive the following: 
            // move the decimal right by 6 to get to a reasonable mantissa form (i.e. [1-9][0-9]*[1-9] where the decimal follows the 1st digit);
            // exp = -6; n = exp + 1 = -5; s = 132764274687
            if (m.startsWith('0.')) {
                // find the index of the 1st significant digit:
                Integer sigIndex = m.indexOfAnyBut('0.');
                // exp = sigIndex - 1; n = sigIndex
                return numToString(m.substring(sigIndex, m.length()), sigIndex);
            
            // e.g. 12321320000.0000343 => does not start with "0."; we can count on not having trailing zeros because then 'm' would have either an
            // exponent or the number would be a double-precise int (i.e. 'm' ends in ".0") and we would've handled either case in preceding logic. 
            // in this example, we derive the following: 
            // move the decimal left by 10 to get a reasonable mantissa form (i.e. [1-9]\.[0-9]*[1-9] where the decimal follows the 1st digit);
            // exp = 10; n = exp + 1 = 11; s = 123213200000000343
            } else {
                // find the index of decimal point:
                Integer decIndex = m.indexOf('.');
                // exp = decIndex - 1; n = decIndex
                return numToString(m.replace('.', ''), decIndex);
            }
        }
    }
    
    // ECMAScript5 9.8.1
    public static String numToString(String s, Integer n) {
        Integer k = s.length();
        if (k <= n && n <= 21) {
            if (n == k)
                return s;
            else
                return s + '0'.repeat(n - k);
        } else if (n > 0 && n <= 21) {
            return s.substring(0, n) + '.' + s.substring(n, s.length());
        } else if (n > -6 && n <= 0) {
            if (n == 0)
                return '0.' + s;
            else
                return '0.' + '0'.repeat(n) + s;
        } else if (k == 1) {
            return s + 'e' + (n - 1 < 0 ? '-' : '+') + Math.abs(n - 1);
        } else
            return s.mid(0, 1) + '.' + s.substring(1, s.length()) + 'e' + (n - 1 < 0 ? '-' : '+') + Math.abs(n - 1);
    }
    
    // Automatic Semicolon Insertion:
    static void matchSemiOrASI(Lexer2 lex, String contextualMsg, Lexer2.Token contextualLoc) {
        Lexer2.Token peek = lex.toks[lex.next];
        // consume a real semicolon, if we're looking at one:
        if (peek.ttype == Lexer2.SEMICOLON)
            lex.next++;
        // if we didn't find a semicolon, and the next token doesn't qualify for ASI, then thow a mismatch error:
        else if (peek.ttype != Lexer2.CLOSE_BRACE && peek.ttype != Lexer2.EOF && peek.leadLineBreaks == 0)
            lex.mismatch(Lexer2.SEMICOLON, contextualMsg, contextualLoc);
        
        // else, the conditions for ASI have been met and thus we "insert" a semicolon token; really we're just allowing the absence of a semicolon...
    }
    
    // parses and instantiates a new CodeContext that represents a global code unit
    public static CodeContext.GlobalCode parseGlobalCode(Context ctx, String moduleUri, String moduleSrcCode, Boolean strict) {
        Lexer2 lex = Lexer2.newLexer(moduleUri, moduleSrcCode);
        Lexer2.Token[] toks = lex.toks;
        CodeContext.GlobalCode globalCode = new CodeContext.GlobalCode(strict);
        BlockContext globalBlock = BlockContext.startGlobalBlock(globalCode);
        
        // a global parse respects directive prologues, allows function decs, and has no break/continue targets at the top level:
        parseSourceElements(lex, globalBlock, PARSE_SOURCE_ELEMENTS, null);
        
        // we should be looking at an EOF, otherwise we have an illegal token:
        if (toks[lex.next].ttype != Lexer2.EOF) {
            lex.unexpectedToken(null);
        }
        
        globalCode.instrucs.add(RET_RES);
        BlockContext.aggregateUp(globalBlock);
        return globalCode;
    }
    
    // parses and instantiates a new CodeContext that represents an eval code unit
    public static CodeContext.Eval parseEvalCode(String srcCode, Boolean strict) {
        Lexer2 lex = Lexer2.newLexer('<eval>', srcCode);
        Lexer2.Token[] toks = lex.toks;
        CodeContext.Eval evalCode = new CodeContext.Eval(strict);
        BlockContext evalBlock = BlockContext.startEvalBlock(evalCode);
        
        // an eval parse respects directive prologues, allows function decs, and has no break/continue targets at the top level:
        parseSourceElements(lex, evalBlock, PARSE_SOURCE_ELEMENTS, null);
        
        // we should be looking at an EOF, otherwise we have an illegal token:
        if (toks[lex.next].ttype != Lexer2.EOF) {
            lex.unexpectedToken(null);
        }
        
        evalCode.instrucs.add(RET_RES);
        BlockContext.aggregateUp(evalBlock);
        return evalCode;
    }

    // used by the built-in Function constructor to parse dynamic function code into an instance of CodeContext.Function. note that it doesn't take a
    // CodeContext or BlockContext argument:
    public static CodeContext.Function parseDynamicFunction(Context ctx, Lexer2.Token loc, String catParams, String body) {
        // 10.1.1 dynamic function code won't be strict unless it contains a "use strict" directive prologue
        CodeContext.Function funcCode = new CodeContext.Function(false, CodeContext.FUNC_DYNAMIC, loc);
        
        Lexer2 lex;
        Lexer2.Token[] toks;
        Lexer2.Token[] params = new Lexer2.Token[]{};
        Lexer2.Token next;
        Integer nextType;
        
        // parse the formal parameters list, if any:
        if (catParams != null && catParams.trim().length() > 0) {
            lex = Lexer2.newLexer('<parameters>', catParams);
            toks = lex.toks;
            do {
                next = toks[lex.next++];
                nextType = next.ttype;
                
                if (nextType == Lexer2.EOF)
                    break;
                
                // else, we have either a 1st param, a leading comma and a subsequent param, or an invalid token --
                // if we've parsed a prior param, then we expect a leading comma before the next param; match it or throw an error:
                if (params.size() > 0)
                    if (nextType == Lexer2.COMMA) {
                        // advance to the token after the comma:
                        next = toks[lex.next++];
                        nextType = next.ttype;
                        // throw an error if this is an illegal trailing comma:
                        if (nextType == Lexer2.EOF)
                            throw new ParseException('Dynamic function parameters may not end in a comma', next);
                    } else
                        lex.backMismatch(Lexer2.COMMA, ' to continue dynamic function parameters, or an end to the parameters');
                
                // at this point, we must expect a formal parameter name token, which must be an Identifier. 
                // !! note that we don't evaluate strict mode restrictions until after we've parsed the FunctionBody:
                if (nextType == Lexer2.IDENTIFIER || nextType >= Lexer2.STRICT_RESERVED_MINIMUM 
                        || nextType == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS)
                    params.add(next);
                else if (nextType == Lexer2.COMMA)
                    throw new ParseException('Dynamic function parameters may not ' 
                            + (params.size() == 0 ? 'lead with a comma' : 'contain consecutive commas'), next);
                else {
                    if (nextType >= Lexer2.RESERVED_WORD_MINIMUM)
                        throw new ParseException('Reserved word \'' 
                                + next.lexeme + '\' may not be used as a dynamic function parameter name', next);
                    else if (nextType >= Lexer2.KEYWORD_MINIMUM)
                        throw new ParseException('Keyword \'' 
                                + next.lexeme + '\' may not be used as a dynamic function parameter name', next);
                    else
                        lex.backMismatch(Lexer2.IDENTIFIER, 'as a ' + (params.size() == 0 ? 'first' : 'subsequent') 
                                + ' dynamic function parameter');
                }
                
            } while (true);
        }
        
        funcCode.formalParams = params;
        lex = Lexer2.newLexer('<dynamic>', body);
        
        // !! create the top-level block only after parsing the formal parameters, because each param is locally declared at the top-level.
        // note that we pass null for the wrapperBlock of a dynamic function:
        BlockContext funcBlock = BlockContext.startFunctionBlock(null, funcCode);
        
        // a function parse allows function decs, parses multiple source elements, and has NO break/continue targets at the top level (note that the
        // targets are unconditionally reset to null upon the start of every function boundary, since they may not span these boundaries):
        parseSourceElements(lex, funcBlock, PARSE_SOURCE_ELEMENTS, null);
        
        // process strict mode restrictions (ECMAScript5 13.1):
        if (funcCode.strict) {
            // note that dynamic functions are all anonymous...
            Map<String, Lexer2.Token> paramsMap = new Map<String, Lexer2.Token>();
            for (Lexer2.Token param: params) {
                if (param.ttype == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS)
                    throw new ParseException('Dynamic function parameter name \'' 
                            + param.lexeme + '\' may not be used for strict mode', param);
                else if (param.ttype >= Lexer2.STRICT_RESERVED_MINIMUM)
                    throw new ParseException('Reserved word \'' 
                            + param.lexeme + '\' may not be used as a dynamic function parameter name', param);
                
                Lexer2.Token priorDupe;
                if ((priorDupe = paramsMap.put(param.lexeme, param)) != null)
                    throw new ParseException('Dynamic function parameter name \'' 
                            + param.lexeme + '\' may not be duplicated in strict mode', param);
            }
        }
        
        // the function's source code is everything between the formal-parameters lead '(' token and the closing '}' tokens, inclusive; note that
        // MFunction's native toString method should prefix this source code with "function ":
        funcCode.srcCode = 'anonymous(' + catParams + ') {\n' + body + '\n}';
        
        // the default return instruc need never be guarded by a JSR, because it can't be enclosed by any deferring block within this same code unit:
        funcCode.instrucs.add(RET_DEF);
        BlockContext.aggregateUp(funcBlock);
        return funcCode;
    }
    
    // parses and instantiates a new CodeContext that represents a function; it will be a function-expr, a function-declaration, a property getter,
    // or a property setter, depending on the supplied "functionType" arg.
    // !! note that this method does not explicitly add a new function-dec to the host context's functionDecs, as that is currently done in the
    // parseSourceElements method
    
    // parses a function declaration or expr; lex is guaranteed to be looking at a "function" keyword token:
    static CodeContext.Function parseFunctionCode(Lexer2 lex, BlockContext hostBlock, Integer functionType, String[] lhsLexicalContext) {
        Lexer2.Token[] toks = lex.toks;
        CodeContext.Function funcCode = new CodeContext.Function(hostBlock.hostCode.strict, functionType, 
                // consume the lead "function" token as the function's location:
                toks[lex.next++]);
        
        funcCode.lhsLexicalContext = lhsLexicalContext;
        
        // the function name must be an ECMAScript Identifier; strict mode additionally doesn't allow the IdentifierNames "eval" and "arguments":
        Lexer2.Token peek = toks[lex.next];
        // if the next token represents a valid object property name, then we'll assume it's meant as this function's name (even if it's invalid for
        // that usgae, e.g. a NumberLiteral):
        if ((Lexer2.TokenClassifications[peek.ttype] & Lexer2.TKLASS_OBJECT_KEY) > 0) {
            // !! for now we'll allow "eval", "arguments", and strict mode future reserved words, but later we'll throw an error for these names if
            // the functionBody is determined to be in strict mode (because of Dierctive Prologues, we must parse the function body before making
            // this determination):
            if (peek.ttype == Lexer2.IDENTIFIER || peek.ttype == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS 
                    || peek.ttype >= Lexer2.STRICT_RESERVED_MINIMUM) {
                funcCode.nameTok = peek;
                funcCode.name = peek.lexeme;
                // advance past the name token:
                lex.next++;
            } else if (peek.ttype >= Lexer2.KEYWORD_MINIMUM)
                throw new ParseException((peek.ttype >= Lexer2.RESERVED_WORD_MINIMUM ? 'Reserved word' : 'Keyword') 
                        + ' \'' + peek.lexeme + '\' may not be used as a function name', peek);
            else
                throw new ParseException((peek.ttype == Lexer2.STRING_LITERAL ? 'String literal' : 'Number literal') 
                        + ' \'' + peek.lexeme + '\' may not be used as a function name', peek);
        }
        
        // a function name is optional only for a function-expr; verify that we've satisfied this requirement for function-declarations:
        if (funcCode.name == null && functionType != CodeContext.FUNC_EXPR)
            lex.unexpectedToken('Function declaration requires a function name');
        
        // parse the function's formal parameters:
        Lexer2.Token[] params = new Lexer2.Token[]{};
        funcCode.formalParams = params;
        
        // for use in error messages:
        String functionTag = funcCode.name == null ? 'anonymous function' : 'function \'' + funcCode.name + '\'';
        Lexer2.Token functionTagLoc = funcCode.name != null ? funcCode.nameTok : funcCode.loc;
        Lexer2.Token openParamsTok = toks[lex.next++];
        // match the '(':
        if (openParamsTok.ttype != Lexer2.OPEN_PAREN)
            lex.backMismatch(Lexer2.OPEN_PAREN, 'to open formal parameters for ' 
                    + functionTag, functionTagLoc);
        
        // parse the formal parameters list:
        Lexer2.Token next;
        Integer nextType;
        do {
            // consume the token after the '(':
            next = toks[lex.next++];
            nextType = next.ttype;
            
            // a legal ')' properly terminates the formal parameters:
            if (nextType == Lexer2.CLOSE_PAREN)
                break;
            
            // else, we have either a 1st param, a leading comma and a subsequent param, or an invalid token --
            // if we've parsed a prior param, then we expect a leading comma before the next param; match it or throw an error:
            if (params.size() > 0)
                if (nextType == Lexer2.COMMA) {
                    // advance to the token after the comma:
                    next = toks[lex.next++];
                    nextType = next.ttype;
                    // throw an error if this is an illegal trailing comma:
                    if (nextType == Lexer2.CLOSE_PAREN)
                        throw new ParseException('Formal parameters for ' + functionTag + ' may not end in a comma', openParamsTok, next);
                } else
                    lex.backMismatch(Lexer2.COMMA, 'or \')\' to continue or close formal parameters for ' + functionTag, openParamsTok);
            
            // at this point, we must expect a formal parameter name token, which must be an Identifier. 
            // !! note that we don't evaluate strict mode restrictions until after we've parsed the FunctionBody:
            if (nextType == Lexer2.IDENTIFIER || nextType >= Lexer2.STRICT_RESERVED_MINIMUM 
                    || nextType == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS)
                params.add(next);
            else if (nextType == Lexer2.COMMA)
                throw new ParseException('Formal parameters for ' + functionTag + ' may not ' 
                        + (params.size() == 0 ? 'lead with a comma' : 'contain consecutive commas'), funcCode.loc, next);
            else {
                if (nextType >= Lexer2.RESERVED_WORD_MINIMUM)
                    throw new ParseException('Reserved word \'' 
                            + next.lexeme + '\' may not be used as a formal parameter name for ' + functionTag, funcCode.loc, next);
                else if (nextType >= Lexer2.KEYWORD_MINIMUM)
                    throw new ParseException('Keyword \'' 
                            + next.lexeme + '\' may not be used as a formal parameter name for ' + functionTag, funcCode.loc, next);
                else
                    lex.backMismatch(Lexer2.IDENTIFIER, 'as a ' + (params.size() == 0 ? 'first' : 'subsequent') 
                            + ' formal parameter for ' + functionTag, openParamsTok);
            }
            
        } while (true);
        
        // match the '{':
        if (toks[lex.next++].ttype != Lexer2.OPEN_BRACE)
            lex.backMismatch(Lexer2.OPEN_BRACE, 'to open body for ' + functionTag, functionTagLoc);
        
        // !! create the top-level block only after parsing the formal parameters, because each param is locally declared at the top-level:
        BlockContext funcBlock = BlockContext.startFunctionBlock(hostBlock, funcCode);
        
        // a function parse allows function decs, parses multiple source elements, and has NO break/continue targets at the top level (note that the
        // targets are unconditionally reset to null upon the start of every function boundary, since they may not span these boundaries):
        parseSourceElements(lex, funcBlock, PARSE_SOURCE_ELEMENTS, null);
        
        // match the '}':
        next = toks[lex.next++];
        if (next.ttype != Lexer2.CLOSE_BRACE)
            lex.backMismatch(Lexer2.CLOSE_BRACE, 'to close body for ' + functionTag, functionTagLoc);
        
        // process strict mode restrictions (ECMAScript5 13.1):
        if (funcCode.strict) {
            // if this is a named function, then evaluate the name against strict mode restrictions and reserved words:
            if (funcCode.nameTok != null) {
                Integer nameTokType = funcCode.nameTok.ttype;
                if (nameTokType == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS)
                    throw new ParseException('The name \'' 
                            + funcCode.nameTok.lexeme + '\' may not be used for a strict mode function', funcCode.nameTok);
                else if (nameTokType >= Lexer2.STRICT_RESERVED_MINIMUM)
                    throw new ParseException('Reserved word \'' 
                            + funcCode.nameTok.lexeme + '\' may not be used as a function name', funcCode.nameTok);
            }
            
            Map<String, Lexer2.Token> paramsMap = new Map<String, Lexer2.Token>();
            for (Lexer2.Token param: params) {
                if (param.ttype == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS)
                    throw new ParseException('Formal parameter name \'' 
                            + param.lexeme + '\' may not be used for strict mode ' + functionTag, funcCode.loc, param);
                else if (param.ttype >= Lexer2.STRICT_RESERVED_MINIMUM)
                    throw new ParseException('Reserved word \'' 
                            + param.lexeme + '\' may not be used as a formal parameter name for ' + functionTag, funcCode.loc, param);
                
                Lexer2.Token priorDupe;
                if ((priorDupe = paramsMap.put(param.lexeme, param)) != null)
                    throw new ParseException('Formal parameter name \'' 
                            + param.lexeme + '\' may not be duplicated in strict mode ' + functionTag, priorDupe, param);
            }
        }
        
        // the function's source code is everything between the formal-parameters lead '(' token and the closing '}' tokens, inclusive; note that
        // MFunction's native toString method should prefix this source code with "function ":
        funcCode.srcCode = lex.stream.substring(openParamsTok.index, next.index + 1);
        
        // the default return instruc need never be guarded by a JSR, because it can't be enclosed by any deferring block within this same code unit:
        funcCode.instrucs.add(RET_DEF);
        BlockContext.aggregateUp(funcBlock);
        return funcCode;
    }
    
    // parses a getter or setter function that's part of an accessor property on an object literal; lex is guaranteed to be looking at a "get" or
    // "set" Identifier token, followed by a valid property name token:
    static CodeContext.Function parseAccessorProperty(Lexer2 lex, BlockContext hostBlock, Integer functionType, String[] lhsLexicalContext) {
        Lexer2.Token[] toks = lex.toks;
        CodeContext.Function funcCode = new CodeContext.Function(hostBlock.hostCode.strict, functionType, 
                // consume the lead "get" or "set" token as the function's location:
                toks[lex.next++]);
        
        // an accessor property name may be an ECMAScript IdentifierName, StringLiteral, or NumberLiteral; here there are no additional restrictions
        // for strict mode:
        Lexer2.Token next = toks[lex.next++];
        Integer nextType = next.ttype;
        funcCode.nameTok = next;
        if (nextType == Lexer2.IDENTIFIER || nextType == Lexer2.STRING_LITERAL || nextType == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS 
                || nextType >= Lexer2.KEYWORD_MINIMUM)
            funcCode.name = next.lexeme;
        else if (nextType == Lexer2.DECIMAL_NUMBER)
            // TODO: review whether the Double.valueOf parse will actually meet the ECMAScript spec:
            funcCode.name = toString(Double.valueOf(next.lexeme));
        else if (nextType == Lexer2.HEX_NUMBER)
            funcCode.name = toString(parseHex(next.lexeme));
        
        if (lhsLexicalContext == null)
            funcCode.lhsLexicalContext = new String[]{ 'Object', funcCode.name };
        else {
            funcCode.lhsLexicalContext = lhsLexicalContext.clone();
            funcCode.lhsLexicalContext.add(funcCode.name);
        }
        
        // parse the function's formal parameters:
        Lexer2.Token[] params = new Lexer2.Token[]{};
        funcCode.formalParams = params;
        
        // for use in error messages:
        String functionTag = (functionType == CodeContext.FUNC_SETTER ? 'setter' : 'getter') + ' \'' + funcCode.name + '\'';
        Lexer2.Token functionTagLoc = funcCode.nameTok;
        Lexer2.Token openParamsTok = toks[lex.next++];
        // match the '(':
        if (openParamsTok.ttype != Lexer2.OPEN_PAREN)
            lex.backMismatch(Lexer2.OPEN_PAREN, 'to open formal parameters for ' 
                    + functionTag, functionTagLoc);
        
        // setter formal params -- must match exactly 1 param:
        if (functionType == CodeContext.FUNC_SETTER) {
            // consume the token after the '(':
            next = toks[lex.next++];
            nextType = next.ttype;
            
            if (nextType == Lexer2.CLOSE_PAREN)
                throw new ParseException('Setter \'' + funcCode.name + '\' requires a value parameter', funcCode.loc, next);
            
            // at this point, we must expect a formal parameter name token, which must be an Identifier. 
            // !! note that we don't evaluate strict mode restrictions until after we've parsed the FunctionBody:
            if (nextType == Lexer2.IDENTIFIER || nextType >= Lexer2.STRICT_RESERVED_MINIMUM 
                    || nextType == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS)
                params.add(next);
            else if (nextType == Lexer2.COMMA)
                throw new ParseException('Value parameter for ' + functionTag + ' may not lead with a comma', funcCode.loc, next);
            else {
                if (nextType >= Lexer2.RESERVED_WORD_MINIMUM)
                    throw new ParseException('Reserved word \'' 
                            + next.lexeme + '\' may not be used as the value parameter name for ' + functionTag, funcCode.loc, next);
                else if (nextType >= Lexer2.KEYWORD_MINIMUM)
                    throw new ParseException('Keyword \'' 
                            + next.lexeme + '\' may not be used as the value parameter name for ' + functionTag, funcCode.loc, next);
                else
                    lex.backMismatch(Lexer2.IDENTIFIER, 'as the value parameter for ' + functionTag, openParamsTok);
            }
            
            // match the ')'
            next = toks[lex.next++];
            if (next.ttype != Lexer2.CLOSE_PAREN)
                if (next.ttype == Lexer2.COMMA)
                    throw new ParseException('Setter \'' + funcCode.name + '\' may not have multiple value parameters', funcCode.loc, next);
                else
                    lex.backMismatch(Lexer2.CLOSE_PAREN, 'to close formal parameters for ' + functionTag, openParamsTok);
        
        // getter formal params -- none allowed:
        } else {
            // match the ')':
            next = toks[lex.next++];
            if (next.ttype != Lexer2.CLOSE_PAREN)
                if (next.ttype == Lexer2.IDENTIFIER || next.ttype == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS
                        || nextType >= Lexer2.KEYWORD_MINIMUM)
                    throw new ParseException('Getter \'' + funcCode.name + '\' may not have any formal parameters', funcCode.loc, next);
                else
                    lex.backMismatch(Lexer2.CLOSE_PAREN, 'to close formal parameters for ' 
                            + functionTag, functionTagLoc);
        }
        
        // match the '{':
        if (toks[lex.next++].ttype != Lexer2.OPEN_BRACE)
            lex.backMismatch(Lexer2.OPEN_BRACE, 'to open body for ' + functionTag, functionTagLoc);
        
        // !! create the top-level block only after parsing the formal parameters, because each param is locally declared at the top-level:
        BlockContext funcBlock = BlockContext.startFunctionBlock(hostBlock, funcCode);
        
        // a function parse allows function decs, parses multiple source elements, and has NO break/continue targets at the top level (note that the
        // targets are unconditionally reset to null upon the start of every function boundary, since they may not span these boundaries):
        parseSourceElements(lex, funcBlock, PARSE_SOURCE_ELEMENTS, null);
        
        // match the '}':
        next = toks[lex.next++];
        if (next.ttype != Lexer2.CLOSE_BRACE)
            lex.backMismatch(Lexer2.CLOSE_BRACE, 'to close body for ' + functionTag, functionTagLoc);
        
        // process strict mode restrictions:
        if (funcCode.strict) {
            for (Lexer2.Token param: params) {
                if (param.ttype == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS)
                    throw new ParseException('Formal parameter name \'' 
                            + param.lexeme + '\' may not be used for strict mode ' + functionTag, funcCode.loc, param);
                else if (param.ttype >= Lexer2.STRICT_RESERVED_MINIMUM)
                    throw new ParseException('Reserved word \'' 
                            + param.lexeme + '\' may not be used as a formal parameter name for ' + functionTag, funcCode.loc, param);
            }
        }
        
        // the function's source code is everything between the formal-parameters lead '(' token and the closing '}' tokens, inclusive:
        funcCode.srcCode = lex.stream.substring(openParamsTok.index, next.index + 1);
        
        // the default return instruc need never be guarded by a JSR, because it can't be enclosed by any deferring block within this same code unit:
        funcCode.instrucs.add(RET_DEF);
        BlockContext.aggregateUp(funcBlock);
        return funcCode;
    }
    
    // used for parsing module code and eval code:
    // parses optional directive prologues followed by 0 or more elements of function declaration or statement
    static final Integer PARSE_SOURCE_ELEMENTS = 0;
    // used for parsing the contents of a block statement; parses 0 or more statements (function declarations not allowed)
    static final Integer PARSE_STATEMENT_LIST  = 1;
    // parses exactly 1 statement (function declarations not allowed), throwing a SyntaxError if it isn't found
    static final Integer PARSE_ONE_STATEMENT   = 2;
    
    // parses consecutive statements; accepts either exactly 1 statement or 0+ statements, depending on the 'exactlyOneStmt' flag:
    static void parseSourceElements(Lexer2 lex, BlockContext hostBlock,
            Integer parseMode, // see above defined PARSE_ types
            String exactlyOneStmtContextualMsg) {
        
        CodeContext hostCode = hostBlock.hostCode;
        Lexer2.Token[] toks = lex.toks;
        Set<String> localLabels;
        Boolean hasLocalLabel = false;
        Lexer2.Token loc;
        Lexer2.Token peek;
        Lexer2.Token next;
        Integer peekType;
        
        // initialize the directive prologue acceptance state:
        Integer parseDirPrologues = parseMode == PARSE_SOURCE_ELEMENTS ? 1 : 0;
        // this outer do-while loop parses multiple stmts:
        do {
            loc = peek = toks[lex.next];
            peekType = peek.ttype;
            
            // labelled stmt: if we're looking at an identifier followed by a colon, then consume as many labels as we encounter; note that in this
            // case the usage of the "eval" and "arguments" IdentifierNames is not restricted in strict mode. if this stmt has no local labels, then
            // the break/continue targets will be inherited as-is from the enclosing contexts (but not to span across function boundaries):
            localLabels = null;
            // an IdentifierName followed by a ':' will either yield a local label or -- if the IdentifierName is a keyword or future reserved word
            // -- a lucid error:
            while ((Lexer2.TokenClassifications[peekType] & Lexer2.TKLASS_IDENT_NAME) > 0 && toks[lex.next + 1].ttype == Lexer2.COLON) {
                // initialize when we encouter the 1st label:
                if (localLabels == null) {
                    localLabels = new Set<String>();
                    // a labelled stmt terminates any active Directive Prologue sequence for this block:
                    if (parseDirPrologues > 0)
                        parseDirPrologues = 0;
                }
                
                // reject the usage of keywords and future reserved words (the latter of which is affected by strict mode) as labels:
                if (peekType >= Lexer2.KEYWORD_MINIMUM) {
                    if (hostCode.strict || peekType < Lexer2.STRICT_RESERVED_MINIMUM)
                        throw new ParseException((peekType < Lexer2.RESERVED_WORD_MINIMUM ? 'Keyword' : 'Future reserved word') 
                                + ' "' + peek.lexeme + '" may not be used as a statement label', peek);
                }
                
                if (localLabels.add(peek.lexeme)) {
                    // check all enclosing blocks in this same codeContext for a duplicate usage of this label:
                    BlockContext enclosingBlock = hostBlock;
                    // terminate when we hit this code unit's top block:
                    while (!enclosingBlock.isTopLevel) {
                        // check all labels in this enclosing block for a match against this local label; any match constitutes a syntax error:
                        if (enclosingBlock.explicitLabels != null && enclosingBlock.explicitLabels.contains(peek.lexeme)) {
                            // TODO: also report the location of the enclosing stmt's conflicting label token:
                            throw new ParseException('Label "' + peek.lexeme + '" is already in use by an enclosing block', loc);
                        }
                        // advance to the next outer block:
                        enclosingBlock = enclosingBlock.outerBlock;
                    }
                    // advance to the next potential label token:
                    peek = toks[lex.next += 2];
                    peekType = peek.ttype;
                    
                } else 
                    throw new ParseException('Label "' + peek.lexeme + '" is a duplicate on this block', loc);
            }
            
            // code-block:
            if (peekType == Lexer2.OPEN_BRACE) {
                // consume the '{':
                lex.next++;
                
                BlockContext stmtBlock = BlockContext.startPlainBlock(hostBlock);
                if (localLabels != null)
                    stmtBlock.explicitLabels = localLabels;
                
                parseSourceElements(lex, stmtBlock, PARSE_STATEMENT_LIST, null);
                
                // match '}'
                if (toks[lex.next++].ttype != Lexer2.CLOSE_BRACE)
                    lex.backMismatch(Lexer2.CLOSE_BRACE, 'to close code block', loc);
                
                // endAddr will be needed (i.e. Instruc.resolvePass2()) if this code block is targeted by any break:
                stmtBlock.endAddr = hostCode.instrucs.size();
                BlockContext.aggregateUp(stmtBlock);
                
            // expression-statement:
            } else if ((Lexer2.TokenClassifications[peekType] & Lexer2.TKLASS_EXPR_STMT_LEAD) > 0) {
                Integer startOffset = hostCode.instrucs.size();
                parseExpr(lex, hostBlock, hostCode.instrucs, LVL_COMMA, ALLOW_IN_OP, TOVAL_RESULT, null);
                matchSemiOrASI(lex, 'to terminate expression-statement', loc);
                
                // allow for a start sequence of Directive Prologues, but stop parsing Directive Prologues (for this hostCode context) as soon as we
                // encounter a stmt that's not a Directive Prologue:
                if (parseDirPrologues > 0) {
                    // we'll start out by assuming that we won't continue parsing Directive Prologues after this expr-stmt (parseDirPrologues is
                    // always decremented at end-of-iteration, which will reduce 1 to 0); we'll override this (set parseDirPrologues = 2) if this
                    // expr-stmt turns out to be a Directive Prologue:
                    parseDirPrologues = 1;
                    Integer nextOffset = hostCode.instrucs.size();
                    // a Directive Prologue expr-stmt must have only 1 instruc:
                    if (nextOffset - startOffset == 1) {
                        Instruc exprIns = hostCode.instrucs[nextOffset - 1];
                        // the lone instruc must a string-value PUSH (i.e. the peek token must be the lowercase string-literal 'use strict'):
                        if (peek.ttype == Lexer2.STRING_LITERAL && 'use strict'.equals(peek.lexeme) 
                                && exprIns.opCode == Instruc.OP_PUSH) {
                            // finally, we must also verify that the original source code -- from which we derived the "use strict" string-
                            // literal token -- does not include any escape sequences or line-continuations. we do this by matching against the
                            // two valid forms: "use strict" and 'use strict':
                            String rawLexeme = lex.stream.substring(peek.index, peek.index + 12);
                            if ('"use strict"'.equals(rawLexeme) || '\'use strict\''.equals(rawLexeme)) {
                                hostCode.strict = true;
                                // !! by bumping up to 2, we allow for a chain of Directive Prologues -- which is actually redundant unless/until we
                                // implement prologues in addition to "use strict", or at least issue a warning for duplicated prologues:
                                parseDirPrologues = 2;
                            }
                        }
                    }
                }

                // for global and eval code, an expr-stmt writes its result (a guaranteed non-Reference value at top-of-stack) into the vm.returnVal
                // and unconditionally pops the stack; this is accomplished by serializing a RESULT instruc. note that an expr-stmt in function code
                // doesn't serialize a RESULT and thus doesn't write into vm.returnVal:
                if (hostCode.codeType < CodeContext.FUNC_CODE_MIN) {
                    // an expr-stmt is the only kind of stmt that will produce a result; note that the RESULT instruc also pops the stack:
                    hostCode.instrucs.add(RESULT);
                // for function code, an expr-statement merely pops the stack:
                } else {
                    hostCode.instrucs.add(POP);
                }
                
                // note that local labels on an ExpressionStatement are discarded, and this type of stmt never creates a new block...
                
            // var declaration:
            } else if (peekType == Lexer2.KW_VAR) {
                parseVarDecList(lex, hostBlock, false);
                matchSemiOrASI(lex, 'to terminate var declaration', loc);
                
                // note that local labels on a VariableDeclaration are discarded, and this type of stmt never creates a new block...
                    
            // function declaration:
            } else if (peekType == Lexer2.KW_FUNCTION) {
                // we now allow function decs within a code block to match the behavior of modern JavaScript implementations, despite this going
                // against spec:
                //if (parseMode != PARSE_SOURCE_ELEMENTS)
                //    throw new ParseException('Function declarations are not allowed inside code blocks', peek);
                
                // !! it's super-important that function decs get "hoisted" to their code units' top-level block -- hence, we use the top-level block
                // instead of the function's static container block as the "hostBlock" argument to parseFunctionCode:
                BlockContext.parsedFunctionDec(hostBlock, parseFunctionCode(lex, hostBlock.hostCode.topLevel, CodeContext.FUNC_DEC, null));
                
                // note that local labels on a FunctionDeclaration are discarded, as they can never be targeted by any of the contained code...
                
            } else if (peekType == Lexer2.KW_THROW || peekType == Lexer2.KW_RETURN) {
                parseValuedAbruptCompletion(lex, hostBlock);
                matchSemiOrASI(lex, 'to terminate ' + peek.lexeme + ' statement', loc);
                
            } else if (peekType == Lexer2.KW_BREAK) {
                // if the break statement has local labels, then we must create a plain block especially to hold them, because it is possible that 
                // this break statement targets 1 of its own labels:
                if (localLabels != null) {
                    BlockContext stmtBlock = BlockContext.startPlainBlock(hostBlock);
                    stmtBlock.explicitLabels = localLabels;
                    
                    parseTargetedAbruptCompletion(lex, stmtBlock);
                    matchSemiOrASI(lex, 'to terminate break statement', loc);
                    
                    stmtBlock.endAddr = hostCode.instrucs.size();
                    BlockContext.aggregateUp(stmtBlock);
                } else {
                    parseTargetedAbruptCompletion(lex, hostBlock);
                    matchSemiOrASI(lex, 'to terminate break statement', loc);
                }
                
            } else if (peekType == Lexer2.KW_CONTINUE) {
                // in the case of continue we discard any localLabels, because this continue statement cannot possibly target any of them:
                parseTargetedAbruptCompletion(lex, hostBlock);
                matchSemiOrASI(lex, 'to terminate continue statement', loc);
                
            // if-else:
            } else if (peekType == Lexer2.KW_IF) {
                // if this statement has local labels, then we must create a plain block especially to hold them, because it's possible that the
                // statement contains a break control that targets 1 of these labels:
                if (localLabels != null) {
                    BlockContext stmtBlock = BlockContext.startPlainBlock(hostBlock);
                    stmtBlock.explicitLabels = localLabels;
                    parseIfElse(lex, stmtBlock);
                    stmtBlock.endAddr = hostCode.instrucs.size();
                    BlockContext.aggregateUp(stmtBlock);
                } else {
                    parseIfElse(lex, hostBlock);
                }
                
            // while, for, and do-while loops:
            } else if (peekType == Lexer2.KW_WHILE || peekType == Lexer2.KW_FOR || peekType == Lexer2.KW_DO) {
                // here we need to do block creation, aggregateUp, endAddr, and continueAddr logic within each parse call, because loops are more
                // complex than plain-block stmts:
                if (peekType == Lexer2.KW_WHILE) {
                    parseWhile(lex, hostBlock, localLabels);
                } else if (peekType == Lexer2.KW_FOR) {
                    parseFor(lex, hostBlock, localLabels);
                } else if (peekType == Lexer2.KW_DO) {
                    parseDoWhile(lex, hostBlock, localLabels);
                    matchSemiOrASI(lex, 'to close do-loop', loc);
                }
                
            // switch:
            } else if (peekType == Lexer2.KW_SWITCH) {
                parseSwitch(lex, hostBlock, localLabels);
                
            // try-catch-finally:
            } else if (peekType == Lexer2.KW_TRY) {
                if (localLabels != null) {
                    BlockContext stmtBlock = BlockContext.startPlainBlock(hostBlock);
                    stmtBlock.explicitLabels = localLabels;
                    parseTry(lex, stmtBlock);
                    stmtBlock.endAddr = hostCode.instrucs.size();
                    BlockContext.aggregateUp(stmtBlock);
                } else {
                    parseTry(lex, hostBlock);
                }
            
            // with:
            } else if (peekType == Lexer2.KW_WITH) {
                if (hostCode.strict)
                    throw new ParseException('Strict mode code may not use \'with\' statements', peek);
                
                parseWith(lex, hostBlock, localLabels);
                
            // empty stmt:
            } else if (peekType == Lexer2.SEMICOLON) {
                lex.next++;
            
            // else, we're looking at token that terminates this stmt list, i.e. an illegal token, a code block terminating '}', a subsequent 'case:'
            // or 'default:' clause (for a switch stmt), or EOF:
            } else {
                if (parseMode == PARSE_ONE_STATEMENT)
                    lex.unexpectedToken('Expected a statement' + (exactlyOneStmtContextualMsg != null ? ' ' + exactlyOneStmtContextualMsg : ''));
                else
                    // if we don't care how many stmts we parsed (i.e. PARSE_STATEMENT_LIST or PARSE_SOURCE_ELEMENTS), then we're done; any
                    // additional validation is up to the caller (e.g. parseGlobalCode will verify that it's looking at EOF): 
                    return;
            }
            
            // we'll only continue parsing Directive Prologues in the case where we just parsed one in this iteration -- in that case, we'll have set
            // parseDirPrologues = 2, so it'll still be greater than 0 even after the following decrement:
            parseDirPrologues--;
            
        } while (parseMode != PARSE_ONE_STATEMENT);
    }
    
    // if isForLoop is true, then we haven't yet determined whether this is a canonical for-loop or a for-in loop (this determination depends on the
    // 1st token after the varDeclarationList). if there is only 1 declared variable, then we'll return its name; for-in loops will use this. if
    // there's more than 1 declared variable, then we'll return null; for-in loops will throw an error in this scenario:
    static Lexer2.Token parseVarDecList(Lexer2 lex, BlockContext hostBlock, Boolean isForLoop) {
        Lexer2.Token[] toks = lex.toks;
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        Lexer2.Token varTok = toks[lex.next];
        // advance past the 'var' token:
        lex.next++;
        // consume the next token, which we expect to be an ident:
        Lexer2.Token next = toks[lex.next++];
        // in a for-in loop, there can only be 1 declared variable, and we need to know its name; based on the expectation that the next token is the
        // 1st ident, we store its lexeme/name for use by these loops:
        Lexer2.Token highlander = next;
        
        do {
            // verify that we received a valid variable name:
            if (next.ttype != Lexer2.IDENTIFIER) {
                // throw an error (all modes) when the token isn't an ECMAScript5 IdentifierName:
                if ((Lexer2.TokenClassifications[next.ttype] & Lexer2.TKLASS_IDENT_NAME) == 0) {
                    lex.backMismatch(Lexer2.IDENTIFIER, 'for variable declaration', varTok);
                // below here, we're left with eval/arguments, keywords, and future reserved words (including strict mode reserved)...
                // strict mode always throws an error when the token is not strictly an IDENTIFIER:
                } else if (hostBlock.hostCode.strict) {
                    if (next.ttype == lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS) {
                        throw new ParseException('"' + next.lexeme + '\" cannot be used as a variable name in strict mode');
                    } else {
                        throw new ParseException((next.ttype < Lexer2.RESERVED_WORD_MINIMUM ? 'Keyword' : 'Reserved word')
                                + ' "' + next.lexeme + '" cannot be used as a variable name' 
                                + (next.ttype >= Lexer2.STRICT_RESERVED_MINIMUM ? ' in strict mode' : ''));
                    }
                // when not in strict mode, we allow "eval", "arguments", and strict mode future reserved words:
                } else if (next.ttype >= Lexer2.KEYWORD_MINIMUM && next.ttype < Lexer2.STRICT_RESERVED_MINIMUM) {
                    throw new ParseException((next.ttype < Lexer2.RESERVED_WORD_MINIMUM ? 'Keyword' : 'Reserved word')
                            + ' "' + next.lexeme + '" cannot be used as a variable name');
                }
                // if we fallthrough here, then the IdentifierName token is ok to use as a variable name in this case...
            }
            
            Lexer2.Token ident = next;
            
            // assignment logic:
            // peek at the next token after the ident; only a '=' or a comma can legally continue this var list. if we're looking at a '=' then we
            // must have an initializer expr for this ident; in that case we'll need to lead with a EnvRef instruc, then serialize the initializer
            // expr's instrucs, and finally and follow with a PUT instruc:
            Instruc.EnvRef assigneeRef;
            if (toks[lex.next].ttype == Lexer2.ASSIGNMENT) {
                // advance past the '=' token:
                lex.next++;
                assigneeRef = new Instruc.EnvRef(ident.lexeme);
                assigneeRef.intVal = ident.ttype;
                // flag this environment ref as a lhs assignee:
                assigneeRef.boolVal = true;
                assigneeRef.loc = ident;
                instrucs.add(assigneeRef);
                // parse the initializer expr:
                parseExpr(lex, hostBlock, instrucs, LVL_ASSIGN, isForLoop ? NO_IN_OP : ALLOW_IN_OP, TOVAL_RESULT, new String[]{ ident.lexeme });
                assigneeRef.putOp = new Instruc.Put(next); // PUT
                instrucs.add(assigneeRef.putOp);
                // !! PUT must always be followed by a POP to remove the lhsRef; additionally, in this case we must additionally POP the rhsVal
                // because it's unused in a var statement:
                instrucs.add(POP);
                instrucs.add(POP);
            }
            // assigneeRef will be null if we didn't parse an initialiser for this var:
            BlockContext.parsedVarDec(hostBlock, ident, assigneeRef);
            
            // a subsequent comma allows the var list to continue (i.e. multiple declared variables); otherwise, we break:
            if (toks[lex.next].ttype == Lexer2.COMMA) {
                // there are multiple declared variables, but the highlander can only be one! so, give up on that. if this dec-list is being parsed
                // for a for-in loop, then it will have to throw an error in response to the multiple declared variables:
                highlander = null;
                // advance past the comma:
                lex.next++;
                // consume the next token, which we expect to be an ident (anything else will result in an error):
                next = toks[lex.next++];
            } else {
                break;
            }
            
        } while (true);
        
        return highlander;
    }
    
    // assumes that lex is pointing at an "if":
    // <ifTest> BRCHF[(<ifElseTest[0]>||<elseBody>||<next>).offset] <ifBody> GOTO[<next>.offset] (<ifElseTest[i]> BRCHF[(<ifElseTest[i+1]>||<elseBody>||<next>).offset] <ifElseBody[i]> GOTO[<next>.offset])* (<elseBody>)? <next> 
    static void parseIfElse(Lexer2 lex, BlockContext hostBlock) {
        Lexer2.Token[] toks = lex.toks;
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        // 0 => if, 1 => else-if, 2 => dangling-else:
        Integer state = 0;
        // we won't be able to resolve the jump offset of this instruc until we're finished parsing this statement:
        Instruc.GoToAddr exitGoTo = new Instruc.GoToAddr();
        Instruc.BranchOnFalse branchTest;
        
        // consume the "if":
        lex.next++;
        // the 1st iteration will be an "if"; subsequent iterations (if any) must be an else-if or dangling-else (up to 1):
        do {
            // if we're not in a dangling-else, then we must parse a test-condition expr:
            if (state != 2) {
                Lexer2.Token openTok = toks[lex.next++];
                if (openTok.ttype != Lexer2.OPEN_PAREN)
                    lex.backMismatch(Lexer2.OPEN_PAREN, 'to open ' + (state == 1 ? 'else if' : 'if') + ' condition', toks[lex.next - 2]);
                
                // serialize the test-condition to instrucs:
                parseExpr(lex, hostBlock, instrucs, LVL_COMMA, ALLOW_IN_OP, TOVAL_RESULT, null);
                // we'll resolve this test cond's follow-up branch offset after we've parsed this branch's body:
                branchTest = new Instruc.BranchOnFalse();
                instrucs.add(branchTest);
                
                if (toks[lex.next++].ttype != Lexer2.CLOSE_PAREN)
                    lex.backMismatch(Lexer2.CLOSE_PAREN, 'to close ' + (state == 1 ? 'else if' : 'if') + ' condition', openTok);
            }
            
            // always parse a single statement to go with the if/else-if/dangling-else (disallow multiple source elements, though the single element
            // may be a code-block); disallow function-decs;
            parseSourceElements(lex, hostBlock, PARSE_ONE_STATEMENT, 
                    // provide a contextual error msg if we don't parse the expected stmt:
                    'under ' + (state == 0 ? 'if' : state == 1 ? 'else if' : 'else') + ' branch');
            
            if (state == 2) {
                // if we just parsed a dangling-else branch, then we're done:
                break;
            } else {
                // after executing a branch's body, we should immediately jump past the end of this if statement:
                instrucs.add(exitGoTo);
                // when a test-condition fails it should jump to the next branch's test-condition (if there is a next else-if), or the start of the 
                // dangling-else body (if there is a dangling-else), or the first instruction after this if-statement, in that order of precedence:
                branchTest.intVal = instrucs.size();
            }
            
            // determine if we're looking at an else-if or a dangling else:
            if (toks[lex.next].ttype == Lexer2.KW_ELSE) {
                if (toks[lex.next + 1].ttype == Lexer2.KW_IF) {
                    lex.next += 2;
                    state = 1; // else-if
                } else {
                    lex.next++;
                    state = 2; // dangling-else
                }
            } else
                break;
            
        } while (true);
        
        exitGoTo.intVal = instrucs.size();
    }
    
    // "throw" and "return" stmts; lex must be pointing at a "throw" or "return" token
    static void parseValuedAbruptCompletion(Lexer2 lex, BlockContext hostBlock) {
        Lexer2.Token[] toks = lex.toks;
        // consume the "throw" or "return" lead token:
        Lexer2.Token leadTok = toks[lex.next++];
        Lexer2.Token peek = toks[lex.next];
        Boolean hasExplicitValueExpr;
        
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        
        // the <valueExpr> will be skipped if we're looking at a ';' or a next token that qualifies for ASI:
        if (peek.ttype == Lexer2.SEMICOLON || peek.leadLineBreaks > 0 || peek.ttype == Lexer2.CLOSE_BRACE || peek.ttype == Lexer2.EOF) {
            // <valueExpr> is required for "throw" stmts:
            if (leadTok.ttype == Lexer2.KW_THROW) {
                throw new ParseException('throw statement requires a value to be thrown' 
                        // if the user appears confused about the application of ASI, then give them a hint:
                        + (peek.ttype != Lexer2.SEMICOLON && peek.leadLineBreaks > 0 ? ' [no lead line-terminator allowed]' : ''), leadTok);
            } else {
                hasExplicitValueExpr = false;
            }
        } else {
            hasExplicitValueExpr = true;
            // else, we're looking at an explicitly provided <valueExpr>; serialize it:
            parseExpr(lex, hostBlock, instrucs, LVL_COMMA, ALLOW_IN_OP, TOVAL_RESULT, null);
        }
        
        if (leadTok.ttype == Lexer2.KW_THROW) {
            // a THROW need never be guarded by JSR's, as its addr redirection is handled by errAddr mappings:
            Instruc ins = new Instruc.ThrowErr();
            ins.loc = leadTok;
            instrucs.add(ins);
        } else {
            if (hostBlock.hostCode.codeType < CodeContext.FUNC_CODE_MIN) {
                throw new ParseException('Illegal return statement; must be contained within a function', leadTok);
            }
            // here we detect explicit <valueExpr>'s that are Tail Call Elimination candidates, and flag the tail CALL instruc appropriately.
            // !! note that tail-call elimination will not occur for a candidate CALL (tail-call elim does not apply to constructors) unless
            // additional runtime criteria are also met; see VirtualMachine.dispatchCall for details.
            if (hasExplicitValueExpr) {
                Instruc tailInstruc = instrucs[instrucs.size() - 1];
                // if we have a tail-CALL instruc, then we must do 1 further check before setting the TCE-candidate bit on this CALL: the expr must
                // not be contained within any deferring block (i.e. tryBlock or catchBlock) in this host code unit, because a deferring block
                // indicates a possible return of control to the host code unit while the CALL is active.
                if (tailInstruc.opCode == Instruc.OP_CALL) {
                    BlockContext block = hostBlock;
                    Boolean hasOuterDeferringBlock;
                    do {
                        if (block.isDeferring) {
                            hasOuterDeferringBlock = true;
                            break;
                        } else if (block.isTopLevel) {
                            break;
                        } else {
                            block = block.outerBlock;
                        }
                    } while (true);
                    
                    if (hasOuterDeferringBlock != true)
                        // now we can flag this CALL as a Tail-Call Elimination candidate, since we have guaranteed that control need not return to
                        // this host code unit after this CALL has been dispatched:
                        tailInstruc.intVal = tailInstruc.intVal == null ? Instruc.TCE_CANDIDATE_BIT : (Instruc.TCE_CANDIDATE_BIT | tailInstruc.intVal);
                }
            }
            
            // we go through the serializeReturn method because it guards the RETURN instruc with 0 or more preceding JSR instrucs (same # of JSR as
            // the # of outer deferring blocks in this code unit), as necessary:
            BlockContext.serializeReturn(hostBlock, hasExplicitValueExpr, leadTok);
        }
    }
    
    // break and continue stmts; lex must be pointing at a "break" or "continue" token:
    static void parseTargetedAbruptCompletion(Lexer2 lex, BlockContext hostBlock) {
        Lexer2.Token[] toks = lex.toks;
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        
        // consume the "break" or "continue" lead token:
        Lexer2.Token leadTok = toks[lex.next++];
        Lexer2.Token peek = toks[lex.next];
        Integer peekType = peek.ttype;
        // this will remain null unless we parse an explicit label target:
        Lexer2.Token targetLabelTok;
        // an explicit target label is optional, and will be skipped if we're looking at a ';' or a next token that qualifies for ASI:
        if (peekType != Lexer2.SEMICOLON && peek.leadLineBreaks == 0 && peekType != Lexer2.CLOSE_BRACE && peekType != Lexer2.EOF) {
            // the target token must be an ECMAScript IdentifierName (note: in this case, 'eval' and 'arguments' are allowed, even in strict mode):
            if ((Lexer2.TokenClassifications[peekType] & Lexer2.TKLASS_IDENT_NAME) == 0)
                lex.mismatch(Lexer2.IDENTIFIER, 'for ' + leadTok.lexeme + ' control\'s target label', leadTok);
            // reject the usage of keywords and future reserved words (the latter of which is affected by strict mode) as labels, but note that
            // strict mode does not restrict the usage of "eval" or "arguments" in this case:
            else if (peekType >= Lexer2.KEYWORD_MINIMUM && (hostBlock.hostCode.strict || peekType < Lexer2.STRICT_RESERVED_MINIMUM))
                throw new ParseException((peekType < Lexer2.RESERVED_WORD_MINIMUM ? 'Keyword' : 'Future reserved word') 
                        + ' "' + peek.lexeme + '" may not be used as a ' + leadTok.lexeme + ' control\'s target', peek);
            
            // if we get here then the target token is a valid format, but below we'll still need to verify that it properly matches an outer
            // target...
            
            // advance past the target token:
            lex.next++;
            targetLabelTok = peek;
        }
        
        if (leadTok.ttype == Lexer2.KW_BREAK) {
            // guards the BREAK with 0 or more JSR's as necessary:
            BlockContext.serializeBreak(hostBlock, targetLabelTok, leadTok);
        } else {
            // guards the CONTINUE with 0 or more JSR's as necessary:
            BlockContext.serializeContinue(hostBlock, targetLabelTok, leadTok);
        }
    }
    
    // assumes that lex is pointing at a "while"; outerContinueTargets corresponding to each member of localLabels will have their resolvedOffset values
    // set appropriately as a product of this method.
    // instrucs:
    // <testExpr> BRCHF[<nextStmt>.offset] <bodyStmt> GOTO[<testExpr.offset>] <nextStmt>
    static void parseWhile(Lexer2 lex, BlockContext hostBlock, Set<String> localLabels) {
        BlockContext loopBlock = BlockContext.startLoopBlock(hostBlock);
        if (localLabels != null) {
            loopBlock.explicitLabels = localLabels;
        }
        
        Lexer2.Token[] toks = lex.toks;
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        loopBlock.continueAddr = instrucs.size();
        
        // consume the "while":
        lex.next++;
        // we should be looking at a '(' to start the test-condition:
        Lexer2.Token openExpr = toks[lex.next++];
        
        if (openExpr.ttype != Lexer2.OPEN_PAREN) {
            lex.backMismatch(Lexer2.OPEN_PAREN, 'to open while-loop condition');
        }
    
        // resolve the goto-next-iteration's addr offset to <testExpr>'s 1st instruc, but withhold this GOTO's serialization for now:
        Instruc.GotoAddr gotoNextIt = new Instruc.GotoAddr(); // the ending GOTO instruc
        gotoNextIt.intVal = loopBlock.continueAddr;
        
        // serialize <testExpr>:
        parseExpr(lex, loopBlock, instrucs, LVL_COMMA, ALLOW_IN_OP, TOVAL_RESULT, null);
        // serialize BRCHF; its jump offset cannot yet be resolved:
        Instruc.BranchOnFalse branchTest = new Instruc.BranchOnFalse(); // also unconditionally pops the <testExpr> result off the stack
        instrucs.add(branchTest);
        
        // we should be looking at a ')' to close the test-condition:
        if (toks[lex.next++].ttype != Lexer2.CLOSE_PAREN) {
            lex.backMismatch(Lexer2.CLOSE_PAREN, 'to close while-loop condition', openExpr);
        }
        
        parseSourceElements(lex, loopBlock, PARSE_ONE_STATEMENT, 'for while-loop body');
        // serialize GOTO:
        instrucs.add(gotoNextIt);
        
        // resolve BRCHF's jump offset to the 1st instruc of <nextStmt>:
        loopBlock.endAddr = branchTest.intVal = instrucs.size();
        BlockContext.aggregateUp(loopBlock);
    }
    
    // assumes that lex is pointing at a "do"; outerContinueTargets corresponding to each member of localLabels will have their resolvedOffset values
    // set appropriately as a product of this method.
    // instrucs:
    // <bodyStmt> <testExpr> BRCHT[<bodyStmt>.offset] <nextStmt>
    static void parseDoWhile(Lexer2 lex, BlockContext hostBlock, Set<String> localLabels) {
        BlockContext loopBlock = BlockContext.startLoopBlock(hostBlock);
        if (localLabels != null) {
            loopBlock.explicitLabels = localLabels;
        }
        
        Lexer2.Token[] toks = lex.toks;
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        // consume the "do":
        lex.next++;
        
        // resolve the BRCHT's jump offset to <bodyStmt>'s 1st instruc, but withhold its serialization for now:
        Instruc.BranchOnTrue branchTest = new Instruc.BranchOnTrue(); // also unconditionally pops the <testExpr> result off the stack
        branchTest.intVal = instrucs.size();
        
        parseSourceElements(lex, loopBlock, PARSE_ONE_STATEMENT, 'for do-loop body');
        
        // we should be looking at a "while" to separate the <bodyStmt> from <testExpr>:
        if (toks[lex.next++].ttype != Lexer2.KW_WHILE) {
            lex.backMismatch(Lexer2.KW_WHILE, 'to close do-loop body');
        }
        
        // we should be looking at a '(' to start the <testExpr>:
        Lexer2.Token openExpr = toks[lex.next++];
        if (openExpr.ttype != Lexer2.OPEN_PAREN) {
            lex.backMismatch(Lexer2.OPEN_PAREN, 'to open do-loop condition');
        }
        
        // the continue addr is the addr of the 1st instruc in <testExpr>:
        loopBlock.continueAddr = instrucs.size();
        
        // serialize <testExpr>:
        parseExpr(lex, loopBlock, instrucs, LVL_COMMA, ALLOW_IN_OP, TOVAL_RESULT, null);
        // now we can serialize the BRCHT:
        instrucs.add(branchTest);
        
        // we should be looking at a ')' to close the test-condition:
        if (toks[lex.next++].ttype != Lexer2.CLOSE_PAREN) {
            lex.backMismatch(Lexer2.CLOSE_PAREN, 'to close do-loop condition', openExpr);
        }
        
        // TODO: if ECMAScript6 block-scope (let and const) were implemented, then we'd need to account for a REST_BLOCK here...
        
        loopBlock.endAddr = instrucs.size();
        BlockContext.aggregateUp(loopBlock);
    }
    
    // assumes that lex is pointing at a "for"; outerContinueTargets corresponding to each member of localLabels will have their resolvedOffset values
    // set appropriately as a product of this method.
    // yikes -- there are 4 variants of for-loop in ECMA-262, and they are not trivial to disambiguate efficiently:
    static void parseFor(Lexer2 lex, BlockContext hostBlock, Set<String> localLabels) {
        // for loops can't determine which block type they are -- loop or enum -- until after they parse a lead expr or semicolon...
        Lexer2.Token[] toks = lex.toks;
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        // consume the "for":
        lex.next++;
        // we should be looking at a '(' to start the test-condition:
        Lexer2.Token openExprsTok = toks[lex.next++];
        
        if (openExprsTok.ttype != Lexer2.OPEN_PAREN)
            lex.backMismatch(Lexer2.OPEN_PAREN, 'to open for-loop expressions');
        
        Boolean isVarType;
        // used by for-var type loops (both canonical and for-in variants):
        Lexer2.Token highlander;
        // used by for-expr loops (both canonical and for-in variants):
        Integer leadExprValType;
        Instruc[] leadExprInstrucs;
        
        // unfortunately, we need to create a new block context before we know exactly which type is appropriate -- loopBlock (canonical-for) or
        // enumBlock (for-in). we start by guessing that we'll parse a canonical-for loop; if this proves wrong then we'll mutate it into an
        // enumBlock:
        BlockContext forBlock = BlockContext.startLoopBlock(hostBlock);
        if (localLabels != null)
            forBlock.explicitLabels = localLabels;
        
        // for-var type:
        // if the first token after the '(' is a 'var', then parseVarDecList[no-in]; we may still have either a canonical for loop or a for-in loop,
        // which cannot be determined until we can peek at the next token after the var-dec list:
        Lexer2.Token peek = toks[lex.next];
        if (peek.ttype == Lexer2.KW_VAR) {
            isVarType = true;
            // if there is only 1 declared variable, then its name will be returned. note that parseVarDecList will serialize instrucs for the
            // var-dec's <varInitializerExpr> components:
            highlander = parseVarDecList(lex, forBlock, true);
        // else, for-expr type:
        } else {
            isVarType = false;
            // the <leadExpr> is optional for canonical for-expr type loops; if we encounter a leading ';' then it has not been included:
            if (peek.ttype != Lexer2.SEMICOLON) {
                // !! we must serialize <leadExpr> instrucs to a separate buffer because with for-in loops, the <leadExpr>'s serialization order is
                // reversed with that of <objectExpr>, relative to their lexical orders. canonical for loops will also need to adjust their intVal
                // jump offsets during serialization:
                leadExprInstrucs = new Instruc[]{};
                // now this gets tricky -- a canonical for loop's lead expr (initialiser) wants a non-Reference value result, but a for-in loop wants
                // a Reference. since we won't know which loop flavor we have until after we parse the expr, we have to stick with the more general
                // form for now (i.e. allow a Reference result). that means if it turns out to be canonical, we'll need to conditionally append an
                // extra TOVAL instruc at that time:
                leadExprValType = parseExpr(lex, forBlock, leadExprInstrucs, LVL_COMMA, NO_IN_OP, ANY_RESULT, null);
            }
        }
        
        peek = toks[lex.next];
        // canonical for loop:
        // if the next token is a ';', then we expect a canonical for loop; the for-var type will serialize as follows (the <varInitialiserExpr>
        // components will have already been serialized above):
        // (<varInitialiserExpr>)* (<testExpr> BRCHF)? <bodyStmt> (<incExpr> POP)? GOTO[(<testExpr>||<bodyStmt>).addr]
        //
        // and, the for-expr type will serialize as follows (the "<leadExpr> POP" will NOT yet have been serialized):
        // (<leadExpr> POP)? (<testExpr> BRCHF)? <bodyStmt> (<incExpr> POP)? GOTO[(<testExpr>||<bodyStmt>).addr]
        if (peek.ttype == Lexer2.SEMICOLON) {
            // we guessed correctly; forBlock can remain its current loopBlock type...
            
            // if we have a <leadExpr> (i.e. no lead var declarations) append the <leadExpr>'s instrucs:
            if (leadExprInstrucs != null) {
                // note that we don't need to adjust addr offsets in the leadExprInstrucs, because all expression-level branching should be in the
                // form of jumps (i.e. fixed addr increments):
                instrucs.addAll(leadExprInstrucs);
                // remember that we parsed <leadExpr> with the ANY_RESULT flag (see above), so it may be a reference value at this point. if it is
                // indeed a ref, then we must mutate the ENVREF/PROPREF => ENVVAL/PROPVAL (potential side-effects 12.6.3[1.b.]):
                if (leadExprValType == REF_VAL) {
                    mutateRefOpToVal(leadExprInstrucs[leadExprInstrucs.size() - 1]);
                }
                // remove the <leadExpr>'s resultant value from the stack:
                instrucs.add(POP);
            }
            
            // !! note that from here on out, the canonical-for loop operates exactly the same for both var and <leadExpr> types...
            
            // advance past the lead ';':
            lex.next++;
            
            // the "next-iteration" GOTO instruc; its addr is resolved now (after <leadExpr> and before <testExpr>), but it must be serialized after
            // the <bodyStmt> and <incExpr>:
            Instruc.GotoAddr gotoNextIt = new Instruc.GotoAddr();
            gotoNextIt.intVal = instrucs.size();
            
            // parse and serialize an optional <testExpr>, if the peek token is not a ';':
            Instruc.BranchOnFalse branchTest;
            if (toks[lex.next].ttype != Lexer2.SEMICOLON) {
                // the <testExpr> is at the Comma level and allows 'in' operators:
                parseExpr(lex, forBlock, instrucs, LVL_COMMA, ALLOW_IN_OP, TOVAL_RESULT, null);
                // BRCHF:
                branchTest = new Instruc.BranchOnFalse(); // also pops top of stack
                instrucs.add(branchTest);
            }
            
            // match the 2nd ';':
            if (toks[lex.next++].ttype != Lexer2.SEMICOLON) {
                lex.backMismatch(Lexer2.SEMICOLON, 'to delimit test and increment expressions in for-loop', openExprsTok);
            }
            
            // parse/serialize an optional <incExpr>, if the peek token is not a ')';
            // !! note that we serialize these instrucs to a separate buffer 'incInstrucs', since they must be appended after the body's instrucs:
            Instruc[] incInstrucs = new Instruc[]{};
            if (toks[lex.next].ttype != Lexer2.CLOSE_PAREN) {
                parseExpr(lex, forBlock, incInstrucs, LVL_COMMA, ALLOW_IN_OP, TOVAL_RESULT, null);
                incInstrucs.add(POP);
            }
            
            // match a ')':
            if (toks[lex.next++].ttype != Lexer2.CLOSE_PAREN) {
                lex.backMismatch(Lexer2.CLOSE_PAREN, 'to close for-loop expressions', openExprsTok);
            }
            
            // parse the loop body:
            parseSourceElements(lex, forBlock, PARSE_ONE_STATEMENT, 'for for-loop body');
            // resolve the continueAddr, which should point to either the start of <incExpr> (if any) or the same target as the GOTO;
            // i.e. GOTO[(<testExpr>||<bodyStmt>).offset]:
            forBlock.continueAddr = incInstrucs.size() > 0 ? instrucs.size() : gotoNextIt.intVal;
            
            // now we can append the instrucs for the <incExpr>. note that we don't need to adjust addr offsets in the incInstrucs, because all
            // expression-level branching should be in the form of jumps (i.e. fixed addr increments):
            instrucs.addAll(incInstrucs);
            
            // GOTO (i.e. next iteration):
            instrucs.add(gotoNextIt);
            
            // TODO: if ECMAScript6 block-scope (let and const) were implemented, then we'd need to account for a REST_BLOCK here...
            
            forBlock.endAddr = instrucs.size();
            // resolve the JMPF (if any) to point to the 1st instruc after this loop:
            if (branchTest != null) {
                branchTest.intVal = forBlock.endAddr;
            }
            
            BlockContext.aggregateUp(forBlock);
            
        // else if the next token is 'in', then we have a for-in, which may lead with either a var declaration (with optional initializer expr) or a
        // lead <lhsExpr>; if the former, then it's a SyntaxError if the var dec list carries more than 1 declared var.
        //
        // a for-in loop serializes as follows (the <varInitialiserExpr>, if provided, will already have been serialized above):
        //     <varInitializerExpr>? <objExpr> ENUM_START[REST_BLOCK.addr] (PUSH[new EnvRef(<varName>)] | <lhsExpr>) ENUM_NEXT[REST_BLOCK.addr]
        //     PUT[POP2] <bodyStmt> GOTO[ENUM_NEXT.addr] REST_BLOCK <nextStmt>
        } else if (peek.ttype == Lexer2.KW_IN) {
            // for-var type validations:
            if (isVarType) {
                // we can't allow multiple declared variables in a for-in loop:
                if (highlander == null) {
                    throw new ParseException('A for-in loop may only declare a single variable', peek);
                }
            // for-expr type validations:
            } else {
                // ensures that the <lhsExpr> is a valid lefthand side by checking its return valueType:
                if (leadExprValType != REF_VAL) {
                    // early SyntaxError; alternatively we could defer to a runtime ReferenceError:
                    throw new ParseException('Invalid left-hand side of for-in loop', peek);
                } else {
                    Instruc prevInstruc = leadExprInstrucs[leadExprInstrucs.size() - 1];
                    // since we've already determined that the expr part is a reference value, we can assert that if we see a prior env ref instruc
                    // then it must comprise the entire <lhsExpr>. note that we can guarantee any OP_ENVREF will not yet be mutated into OP_STKREF, 
                    // because that can't occur until the pass2 compilation of this host code unit:
                    if (prevInstruc.opCode == Instruc.OP_ENVREF) {
                        if (hostBlock.hostCode.strict && prevInstruc.intVal == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS) {
                            throw new ParseException('Invalid left-hand side of for-in loop; cannot assign to "' 
                                    + prevInstruc.strVal + '" in strict mode', peek);
                        } else {
                            // the for-in lhs is comprised of an environment ref; flag it as an assignee so that pass2 compilation may throw an early
                            // SyntaxError if it binds to an immutable (strict mode), or convert it to a no-op (sloppy mode):
                            prevInstruc.boolVal = true;
                        }
                    }
                }
            }
            
            // we guessed wrong in our initial block instantiation; take the canonical-for loopBlock we've started and mutate it into an enumBlock:
            BlockContext.mutateLoopBlockToEnum(forBlock);
            
            // advance past the 'in':
            Lexer2.Token inTok = toks[lex.next++];
            
            // serialize <objExpr>; it will naturally occupy the 1st (any only) stack slot reserved for this enumBlock. unlike other loop expressions,
            // we'll retain its value on the stack (i.e. we don't POP it) for the duration of this block:
            parseExpr(lex, forBlock, instrucs, LVL_COMMA, ALLOW_IN_OP, TOVAL_RESULT, null);
            
            // ENUM_START takes the result from <objExpr> atop the stack, and performs operations to convert it to a String[] representing the full
            // set of prop names on that obj. jumps immediately to REST_BLOCK if the <objExpr> value is null or undefined:
            Instruc.EnumStart enumStart = new Instruc.EnumStart();
            enumStart.loc = inTok;
            instrucs.add(enumStart);
            
            // continue addr should point at the 1st instruc after the ENUM_START, i.e. the PUSH[new EnvRef(<varName>)].addr or <lhsExpr>.addr:
            forBlock.continueAddr = instrucs.size();
            Instruc.GoToAddr gotoNextIt = new Instruc.GoToAddr();
            gotoNextIt.intVal = forBlock.continueAddr;
            
            // both forms of for-in must be able to identify a ref op for the lhs (always an ENVREF in the var case):
            Instruc lhsRefOp;
            // if this is a for-var type, then there must be a single declared variable:
            if (isVarType) {
                // ENVREF[<varName>]:
                lhsRefOp = new Instruc.EnvRef(highlander.lexeme);
                lhsRefOp.intVal = highlander.ttype;
                lhsRefOp.loc = highlander;
                instrucs.add(lhsRefOp);
                BlockContext.parsedEnvRef(forBlock, (Instruc.EnvRef) lhsRefOp);
            // else we must have a <lhsExpr>; append its instrucs:
            } else {
                // we knw that the last instruc must be an ENVREF or PROPREF, since the resultant valueType is REF_VAL:
                lhsRefOp = leadExprInstrucs[leadExprInstrucs.size() - 1];
                // note that we don't need to adjust addr offsets in the leadExprInstrucs, because all expression-level branching should be in the
                // form of jumps (i.e. fixed addr increments):
                instrucs.addAll(leadExprInstrucs);
            }
            
            // !! note that from here on out, the for-in loop operates exactly the same for both for-var and for-expr types...
            
            // ENUM_NEXT takes the String[] at stack[top - 1] (note: the lhsRef is atop the stack at this time) and shift()'s it to get the new prop
            // name, which is immediately pushed atop the stack (i.e. now we're left with lhs-ref at pen and rhs-value at top). if the String[] is
            // empty, then it jumps to the REST_BLOCK:
            Instruc.EnumNext enumNext = new Instruc.EnumNext();
            enumNext.loc = inTok;
            instrucs.add(enumNext);
            
            // PUT the next property name (value atop stack) into the lhsRef (lhsRefOp is an ENVREF or PROPREF). we record the PUT instruc into
            // the ref instruc (if ENVREF) because pass2 must mutate that PUT into an IMMUT if the ref is an ENVREF that becomes a STKREF bound to
            // an immutable:
            Instruc.Put putOp = new Instruc.Put(enumNext.loc);
            if (lhsRefOp.opCode == Instruc.OP_ENVREF) {
                ((Instruc.EnvRef) lhsRefOp).putOp = putOp;
            }
            instrucs.add(putOp); // PUT
            // 2 pops because both lhsRef and rhsVal should be cleared off the stack:
            instrucs.add(POP);
            instrucs.add(POP);
            
            // match a ')':
            if (toks[lex.next++].ttype != Lexer2.CLOSE_PAREN) {
                lex.backMismatch(Lexer2.CLOSE_PAREN, 'to close for-in expressions', openExprsTok);
            }
            
            // serialize <bodyStmt>:
            parseSourceElements(lex, forBlock, PARSE_ONE_STATEMENT, 'for for-in body');
            // GOTO[ENUM_NEXT.addr]:
            instrucs.add(gotoNextIt);
            
            Integer restBlockAddr = instrucs.size();
            // resolve the ENUM_START (jump upon for-in on null or undefined) and ENUM_NEXT (jump after the last enumerable property) jump offsets;
            // they should point to the block-terminating REST_BLOCK instruc:
            enumStart.intVal = enumNext.intVal = restBlockAddr;
            
            // REST_BLOCK; we use the createRestBlock method instead of creating this instruc directly, as it needs to be registered with the top-
            // level block (like the other BlockControl instrucs, e.g. BreakControl):
            instrucs.add(BlockContext.createRestBlock(forBlock));
            
            // note that BREAK instrucs calculate block cleanup on their own, so they can jump past the REST_BLOCK:
            forBlock.endAddr = instrucs.size();
            BlockContext.aggregateUp(forBlock);
            
        } else {
            lex.mismatch(Lexer2.SEMICOLON, 'or \'in\' to continue for-loop', openExprsTok);
        }
    }
    
    // assumes that lex is pointing at 'switch'
    //
    // instruction serialization layout (note: N may be any integer value >= 0, and i repeats from 0 to N-1, inclusive):
    // 
    // <switchExpr> 
    // GOTO:0[(<caseExpr_0>||POP).addr]
    // (<caseStmts_i>){i=0..N-1}
    // GOTO:1[<nextStmt>.addr] 
    // (<caseExpr_i> SWCHCMP[<caseStmts_i>.addr]){i=0..N-1}
    // POP
    // (GOTO:2[<defaultStmts>.addr])?
    // <nextStmt>
    //
    // !! note that SWCHCMP acts like a BRCHT/BRCHF, except that its jump is contingent upon a strict-equality match on the 2 non-ref values atop
    // the stack: [... <switchExpr>, <caseExprN>] 
    //
    // !! note that we serialize the case/default stmt-lists before the <caseExpr_i>'s, because it's a lot easier (and usually quicker) to addrOffset-
    // adjust the former than the latter -- i.e. expressions can't contain pre-resolved BreakControl/ContinueControl instrucs that should be excluded
    // from adjustment, and they can't have stmt-level jump instrucs like SWCHCMP/ENUM_NEXT, etc:
    static void parseSwitch(Lexer2 lex, BlockContext hostBlock, Set<String> localLabels) {
        Lexer2.Token[] toks = lex.toks;
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        // consume the "switch":
        Lexer2.Token switchTok = toks[lex.next++];
        
        // match a '(' to open the <switchExpr>:
        Lexer2.Token openParenTok = toks[lex.next++];
        if (openParenTok.ttype != Lexer2.OPEN_PAREN) {
            lex.backMismatch(Lexer2.OPEN_PAREN, 'to open switch expression');
        }
        BlockContext switchBlock = BlockContext.startSwitchBlock(hostBlock);
        if (localLabels != null) {
            switchBlock.explicitLabels = localLabels;
        }
        
        // serialize the one and only <switchExpr>:
        parseExpr(lex, switchBlock, instrucs, LVL_COMMA, ALLOW_IN_OP, TOVAL_RESULT, null);
        
        // match a ')' to close the <switchExpr>:
        if (toks[lex.next++].ttype != Lexer2.CLOSE_PAREN) {
            lex.backMismatch(Lexer2.CLOSE_PAREN, 'to close switch expression', openParenTok);
        }
        // a switch stmt starts with a GOTO that targets (<caseExpr_0>||POP).addr; its jump addr will be resolved after we've parsed & serialized all
        // of <caseStmts_i>{N=0..N-1}.
        // TODO: in ECMAScript6, a switch stmt would need a special lead instruc that could do block-level Declaration Binding Instatntiation (i.e.
        // if necessary for any contains let/const decs):
        Instruc.GoToAddr switchStart = new Instruc.GoToAddr();
        switchStart.loc = switchTok;
        instrucs.add(switchStart);
        
        // match a '{' to open the CaseBlock:
        Lexer2.Token openBraceTok = toks[lex.next++];
        if (openBraceTok.ttype != Lexer2.OPEN_BRACE) {
            lex.backMismatch(Lexer2.OPEN_BRACE, 'to open case block');
        }
        
        Lexer2.Token peek = toks[lex.next];
        Integer defaultAddr;
        Lexer2.Token defaultLoc;
        // the addr of the start of each case's stmts-list, in the order each case is encountered:
        Integer[] caseStmtsAddrs = new Integer[]{};
        // collects the SWCHCMP instrucs we've serialized for this statement, in source order:
        Instruc.SwitchCmp[] switchCmps = new Instruc.SwitchCmp[0];
        // a buffer to hold the serialization of (<caseExpr_i> SWITCH_CMP[<caseStmts_i>.addr])*, since we're appending them contrary to source order:
        Instruc[] caseExprsAndSwitchCmps = new Instruc[0];
        // continue parsing a next CaseClause or DefaultClause as long as our peek is a "case" or "default", but throw an error if we encounter a 2nd
        // DefaultClause:
        while (peek.ttype == Lexer2.KW_CASE || peek.ttype == Lexer2.KW_DEFAULT) {
            // advance past the "case" or "default":
            lex.next++;
            
            if (peek.ttype == Lexer2.KW_CASE) {
                caseStmtsAddrs.add(instrucs.size());
                // serialize this <caseExpr_i> to a buffer, because its serialization position does not correspond to its lexical order relative to
                // the corresponding <caseStmts_i>:
                parseExpr(lex, switchBlock, caseExprsAndSwitchCmps, LVL_COMMA, ALLOW_IN_OP, TOVAL_RESULT, null);
                // create the SWITCH_CMP; its branch addr offset will be resolved later:
                Instruc.SwitchCmp switchCmp = new Instruc.SwitchCmp();
                switchCmp.loc = peek;
                switchCmps.add(switchCmp);
                caseExprsAndSwitchCmps.add(switchCmp);
                
                // match a ':'
                if (toks[lex.next++].ttype != Lexer2.COLON) {
                    lex.backMismatch(Lexer2.COLON, 'to punctuate case clause');
                }
                // serialize this <caseStmts_i>:
                parseSourceElements(lex, switchBlock, PARSE_STATEMENT_LIST, null);
            } else if (defaultAddr == null) {
                defaultLoc = peek;
                defaultAddr = instrucs.size();
                // match a ':'
                if (toks[lex.next++].ttype != Lexer2.COLON) {
                    lex.backMismatch(Lexer2.COLON, 'to punctuate default clause');
                }
                // serialize <defaultStmts>:
                parseSourceElements(lex, switchBlock, PARSE_STATEMENT_LIST, null);
            } else {
                throw new ParseException('switch statement cannot have multiple default clauses', peek);
            }
            
            peek = toks[lex.next];
        }
        
        // match a '}' to close the CaseBlock:
        if (toks[lex.next++].ttype != Lexer2.CLOSE_BRACE) {
            lex.backMismatch(Lexer2.CLOSE_BRACE, 'to close case block', openBraceTok);
        }
        
        // now, having serialized <caseStmts_i> for all case-clauses, and <defaultStmts>, we can:
        // 1. serialize the GOTO:1; its jump offset will be resolved later:
        Instruc.GoToAddr gotoEnd = new Instruc.GoToAddr();
        instrucs.add(gotoEnd);
        // 2. resolve the GOTO:0's jump addr -- i.e. jump past case/default clause bodies to the <caseExpr_0> (start of switching logic) OR the POP
        // (pop <switchExpr> value) if there are no caseExpr's:
        switchStart.intVal = instrucs.size();
        // 3. resolve the addr offset for each SWCHCMP we've instantiated (i.e. target its corresponding <caseStmts_i>):
        for (Integer i=0; i < switchCmps.size(); i++) {
            switchCmps[i].intVal = caseStmtsAddrs[i];
        }
        // 4. append all the SWCHCMP and <caseExpr_i> instructions we've accumulated in that buffer. note that we don't need to adjust addr offsets
        // in the caseExprsAndSwitchCmps instrucs, because all expression-level branching should be in the form of jumps (i.e. fixed addr increments):
        instrucs.addAll(caseExprsAndSwitchCmps);
        
        // if we make it through all SWITCH_CMP instrucs without a match, then pop the result from <switchExpr>, which currently resides atop the
        // stack:
        instrucs.add(POP);
        
        // if there was a default clause, then serialize the GOTO:2 (i.e. goto <defaultStmts>.addr) and resolve its jump offset:
        if (defaultAddr != null) {
            Instruc.GoToAddr gotoDefault = new Instruc.GoToAddr();
            gotoDefault.intVal = defaultAddr;
            instrucs.add(gotoDefault);
        }
        
        // TODO: if ECMAScript6 block-scope (let and const) were implemented, then we'd need to account for a REST_BLOCK here...
        
        // finally, we can resolve the GOTO:1's jump addr (i.e. normal completion; goto end) and the target addr for contained BREAK ops:
        gotoEnd.intVal = switchBlock.endAddr = instrucs.size();
        BlockContext.aggregateUp(switchBlock);
    }
    
    // instruction serialization layout:
    //
    // STORE_LEX
    // <tryStmts>
    // JSR[curryVal=false][subAddr=<finallyStmts>.addr||null][retAddr=GOTO:0.addr][startBlock=targetBlock=<tryBlock>]
    // GOTO:0[<nextStmt>.addr]
    // 
    // CATCH[strVal=<errorVarTok>.lexeme][targetBlock=<catchBlock>]
    // <catchStmts>
    // JSR[curryVal=false][subAddr=<finallyStmts>.addr||null][retAddr=GOTO:1.addr][startBlock=targetBlock=<catchBlock>]
    // GOTO:1[<nextStmt>.addr]
    //
    // JSR_IC[curryVal=true][subAddr=<finallyStmts>.addr||null][retAddr=THROW.addr][targetBlock=<catchBlock>||<tryBlock>]
    // THROW ; TODO: should we make a separate THROW_IC instruc that maintains original stack trace, so that THROW can add re-throw stacks?
    // 
    // <finallyStmts>
    // RSR[targetBlock=<finallyBlock>]
    // 
    // <nextStmt>
    static void parseTry(Lexer2 lex, BlockContext hostBlock) {
        
        Lexer2.Token[] toks = lex.toks;
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        // consume the "try":
        Lexer2.Token tryTok = toks[lex.next++];
        
        // !! BlockControl type instrucs need to be registered with the closest top-level block, because they require subsequent pass2 processing.
        // since we're directly creating & serializing multiple such instrucs in this method, we'll collect them in the following list and then
        // "register" them all at once:
        Instruc.BlockControl[] pass2Instrucs = new Instruc.BlockControl[]{};
        
        // STORE_LEX
        instrucs.add(new Instruc.StoreLex());
        BlockContext tryBlock = BlockContext.startTryBlock(hostBlock);
        // we don't include STORE_LEX in the [startAddr..endAddr) range:
        Integer tryBlockStartAddr = instrucs.size();
        // match a '{' to open the tryBlock
        Lexer2.Token openTryBlock = toks[lex.next++];
        if (openTryBlock.ttype != Lexer2.OPEN_BRACE) {
            lex.backMismatch(Lexer2.OPEN_BRACE, 'to open try clause');
        }
        // <tryStmts>
        parseSourceElements(lex, tryBlock, PARSE_STATEMENT_LIST, null);
        // note that [startAddr..endAddr) doesn't include the entry STORE_LEX nor exit JSR+GOTO:0, because these instrucs don't need errAddr
        // mappings:
        tryBlock.endAddr = instrucs.size();
        // match a '}' to close the TryBlock:
        if (toks[lex.next++].ttype != Lexer2.CLOSE_BRACE) {
            lex.backMismatch(Lexer2.CLOSE_BRACE, 'to close try clause', openTryBlock);
        }
        // JSR[curryVal=false][subAddr=<finallyStmts>.addr][retAddr=GOTO:0.addr][startBlock=targetBlock=<tryBlock>]
        Instruc.JSR exitTryBlockJSR = new Instruc.JSR();
        exitTryBlockJSR.boolVal = false; // curryVal=false
        exitTryBlockJSR.startBlock = tryBlock; // TODO: consider allowing JSR to specify a single-block restore (i.e. leave startBlock null)
        exitTryBlockJSR.targetBlock = tryBlock;
        instrucs.add(exitTryBlockJSR);
        exitTryBlockJSR.returnAddr = instrucs.size(); // note: intVal (i.e. subAddr) will be resolved later iff we encounter a finally clause
        
        pass2Instrucs.add(exitTryBlockJSR);
        
        // GOTO:0[<nextStmt>.addr]
        Instruc.GoToAddr exitTryBlockGoto = new Instruc.GoToAddr();
        instrucs.add(exitTryBlockGoto); // intVal (jump addr) will be resolved after we complete all instruc serialization
        
        BlockContext catchBlock;
        Integer catchBlockStartAddr;
        Instruc.JSR exitCatchBlockJSR;
        Instruc.GoToAddr exitCatchBlockGoto;
        if (toks[lex.next].ttype == Lexer2.KW_CATCH) {
            Lexer2.Token catchTok = toks[lex.next++];
            if (toks[lex.next++].ttype != Lexer2.OPEN_PAREN)
                lex.backMismatch(Lexer2.CLOSE_BRACE, 'to open catch clause error declaration', catchTok);
            
            Lexer2.Token errorVarTok = toks[lex.next++];
            // verify that we received a valid error name token:
            if (errorVarTok.ttype != Lexer2.IDENTIFIER) {
                // throw an error (all modes) when the token isn't an ECMAScript IdentifierName:
                if ((Lexer2.TokenClassifications[errorVarTok.ttype] & Lexer2.TKLASS_IDENT_NAME) == 0) {
                    lex.backMismatch(Lexer2.IDENTIFIER, 'for catch clause error name', catchTok);
                // below here, we're left with eval/arguments, keywords, and future reserved words (including strict mode reserved);
                // strict mode always throws an error when the token is not strictly an IDENTIFIER:
                } else if (hostBlock.hostCode.strict) {
                    if (errorVarTok.ttype == lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS)
                        throw new ParseException('You may not use \'' + errorVarTok.lexeme 
                                + '\' as a catch clause error name in strict mode');
                    else
                        throw new ParseException('You may not use ' 
                                + (errorVarTok.ttype < Lexer2.RESERVED_WORD_MINIMUM 
                                        ? 'keyword' 
                                        : (errorVarTok.ttype < Lexer2.STRICT_RESERVED_MINIMUM 
                                                ? 'reserved word' 
                                                : 'strict mode reserved word')) 
                                + ' \'' + errorVarTok.lexeme + '\' as a catch clause error name');
                // when not in strict mode, we allow "eval", "arguments", and strict mode future reserved words:
                } else if (errorVarTok.ttype >= Lexer2.KEYWORD_MINIMUM && errorVarTok.ttype < Lexer2.STRICT_RESERVED_MINIMUM) {  
                    throw new ParseException('You may not use ' 
                            + (errorVarTok.ttype < Lexer2.RESERVED_WORD_MINIMUM ? 'keyword' : 'reserved word') 
                            + ' \'' + errorVarTok.lexeme + '\' as a catch clause error name');
                }
                // if we fallthrough here, then the this non-Identifier IdentifierName token is valid for use as the error var name...
            }

            // match ')' then '{'
            if (toks[lex.next++].ttype != Lexer2.CLOSE_PAREN)
                lex.backMismatch(Lexer2.CLOSE_PAREN, 'to close catch clause error declaration');
            Lexer2.Token openCatchBlockTok = toks[lex.next++];
            if (openCatchBlockTok.ttype != Lexer2.OPEN_BRACE)
                lex.backMismatch(Lexer2.OPEN_BRACE, 'to open catch clause');
            
            // every instruc in <tryStmts>, excluding those already with an errAddr (i.e. from a nested tryBlock/catchBlock), should map its
            // errAddr to this upcoming CATCH instruc:
            Integer thisCatchAddr = instrucs.size();
            for (Integer i=tryBlockStartAddr; i < tryBlock.endAddr; i++) {
                Instruc ins = instrucs[i];
                if (ins.errAddr == null)
                    ins.errAddr = thisCatchAddr;
            }
            
            catchBlock = BlockContext.startCatchBlock(hostBlock);
            // declare the error var as a block-local dec on the new catchBlock:
            // note: in ECMAScript5, this is the only case of a non-top-level block that has its own block-local declaration! 
            catchBlock.localDecNames = new Set<String> { errorVarTok.lexeme };
            // CATCH
            Instruc.CatchStart catchStart = new Instruc.CatchStart();
            catchStart.strVal = errorVarTok.lexeme;
            catchStart.targetBlock = catchBlock;
            instrucs.add(catchStart);
            
            pass2Instrucs.add(catchStart);
            
            // note that [startAddr..endAddr) doesn't include the entry CATCH nor exit JSR+GOTO:1, because these instrucs don't need errAddr
            // mappings:
            catchBlockStartAddr = instrucs.size();
            // <catchStmts>
            parseSourceElements(lex, catchBlock, PARSE_STATEMENT_LIST, null);
            catchBlock.endAddr = instrucs.size();
            
            // match '}'
            if (toks[lex.next++].ttype != Lexer2.CLOSE_BRACE)
                lex.backMismatch(Lexer2.CLOSE_BRACE, 'to close catch clause', openCatchBlockTok);
            
            // JSR[curryVal=false][subAddr=<finallyStmts>.addr][retAddr=GOTO:1.addr][startBlock=targetBlock=<catchBlock>]
            exitCatchBlockJSR = new Instruc.JSR();
            exitCatchBlockJSR.boolVal = false; // curryVal=false
            exitCatchBlockJSR.startBlock = catchBlock;
            exitCatchBlockJSR.targetBlock = catchBlock;
            instrucs.add(exitCatchBlockJSR);
            exitCatchBlockJSR.returnAddr = instrucs.size();  // intVal (i.e. subAddr) will be resolved later
            
            pass2Instrucs.add(exitCatchBlockJSR);
            
            // GOTO:1[<nextStmt>.addr]
            exitCatchBlockGoto = new Instruc.GoToAddr();
            instrucs.add(exitCatchBlockGoto); // intVal (jump addr) will be resolved after we complete all instruc serialization
        }
        // else, we don't have an explicit catch clause...
        
        // either the <tryStmts> (if no explicit catchBlock) or <catchStmts> instrucs (excluding those already with an errAddr) are subject to an
        // implicit catch, and thus should set their errAddr to the addr of the upcoming implicit catch instrucs:
        Integer implicitCatchAddr = instrucs.size();
        BlockContext subjectToImplicitCatch = catchBlock != null ? catchBlock : tryBlock;
        for (Integer i=catchBlock != null ? catchBlockStartAddr : tryBlockStartAddr; i < subjectToImplicitCatch.endAddr; i++) {
            Instruc ins = instrucs[i];
            if (ins.errAddr == null)
                ins.errAddr = implicitCatchAddr;
        }
        
        // implicit catch instrucs:
        Instruc.JSR_IC jsrIC = new Instruc.JSR_IC();
        jsrIC.boolVal = true; // curryVal=true; we need to curry the thrown value
        jsrIC.targetBlock = subjectToImplicitCatch; // note that for a JSR_IC, startBlock is unused
        instrucs.add(jsrIC);
        jsrIC.returnAddr = instrucs.size(); // intVal (i.e. subAddr) will be resolved later
        
        pass2Instrucs.add(jsrIC);
        
        // TODO: ReThrow or ThrowErr? also, revamp impl logic for THROW instruc:
        Instruc.ThrowErr throwErr = new Instruc.ThrowErr();
        // TODO: should we set a loc for this THROW?
        instrucs.add(throwErr);
        
        // parse optional finally clause:
        BlockContext finallyBlock;
        if (toks[lex.next].ttype == Lexer2.KW_FINALLY) {
            lex.next++;
            // match '{'
            Lexer2.Token openFinallyBlockTok = toks[lex.next++];
            if (openFinallyBlockTok.ttype != Lexer2.OPEN_BRACE)
                lex.backMismatch(Lexer2.OPEN_BRACE, 'to open finally clause');
            
            // !! we have an explicit finally clause, so resolve the subroutine addr for all the preceding JSR instrucs (subAddr attributes are left
            // null when there is no finally clause):
            exitTryBlockJSR.intVal = instrucs.size(); // subAddr=<finallyStmts>.addr
            if (catchBlock != null) {
                exitCatchBlockJSR.intVal = exitTryBlockJSR.intVal; // subAddr=<finallyStmts>.addr
            }
            jsrIC.intVal = exitTryBlockJSR.intVal; // subAddr=<finallyStmts>.addr
        
            finallyBlock = BlockContext.startFinallyBlock(hostBlock);
            // <finallyStmts>
            parseSourceElements(lex, finallyBlock, PARSE_STATEMENT_LIST, null);
            // RSR
            Instruc.RSR rsr = new Instruc.RSR();
            rsr.targetBlock = finallyBlock;
            instrucs.add(rsr);
            
            pass2Instrucs.add(rsr);
            
            // match '}'
            if (toks[lex.next++].ttype != Lexer2.CLOSE_BRACE)
                lex.backMismatch(Lexer2.CLOSE_BRACE, 'to close finally clause', openFinallyBlockTok);
        }
        
        // resolve the try and catch clauses' exit goto addr:
        exitTryBlockGoto.intVal = instrucs.size(); // GOTO:0[intVal=<nextStmt>.addr]
        if (catchBlock != null) {
            exitCatchBlockGoto.intVal = exitTryBlockGoto.intVal; // GOTO:1[intVal=<nextStmt>.addr]
        }
        
        // register the BlockControl instrucs we've directly created in this method; they have components that must be resolved in pass2:
        BlockContext topLevel = hostBlock.hostCode.topLevel;
        if (topLevel.topLevelBlockControls == null) {
            topLevel.topLevelBlockControls = pass2Instrucs;
        } else {
            topLevel.topLevelBlockControls.addAll(pass2Instrucs);
        }
        
        // perform aggregateUp on each parsed block:
        BlockContext.aggregateUp(tryBlock);
        if (catchBlock != null) {
            BlockContext.aggregateUp(catchBlock); 
        }
        if (finallyBlock != null) {
            BlockContext.aggregateUp(finallyBlock);
        }
    }
    
    // instruction serialization layout:
    //
    // <objExpr>
    // WITH
    // <bodyStmt>
    // RESTBLOK[targetBlock=<withBlock>]
    // <nextStmt>
    static void parseWith(Lexer2 lex, BlockContext hostBlock, Set<String> localLabels) {
        
        Lexer2.Token[] toks = lex.toks;
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        // consume the "with":
        Lexer2.Token withTok = toks[lex.next++];
        Lexer2.Token openExprTok = toks[lex.next++];
        if (openExprTok.ttype != Lexer2.OPEN_PAREN)
            lex.backMismatch(Lexer2.OPEN_PAREN, 'to open with expression');
        
        // <objExpr>:
        parseExpr(lex, hostBlock, instrucs, LVL_COMMA, ALLOW_IN_OP, TOVAL_RESULT, null);
        
        if (toks[lex.next++].ttype != Lexer2.CLOSE_PAREN)
            lex.backMismatch(Lexer2.CLOSE_PAREN, 'to close with expression', openExprTok);
        
        BlockContext withBlock = BlockContext.startWithBlock(hostBlock);
        if (localLabels != null)
            withBlock.explicitLabels = localLabels;
        
        // WITH:
        Instruc.WithStart withStart = new Instruc.WithStart();
        withStart.loc = withTok;
        instrucs.add(withStart);
        
        // <withStmt>:
        parseSourceElements(lex, hostBlock, PARSE_ONE_STATEMENT, 'for with statement body');

        // RESTBLOK:
        instrucs.add(BlockContext.createRestBlock(withBlock));
        withBlock.endAddr = instrucs.size();
        
        BlockContext.aggregateUp(withBlock);
    }
    
    // TODO: flesh out serializeToken(Integer ttype) (e.g. print ':' instead of <ttype 4>)
    
    // For our expression parser we do something special: an almost purely iterative (the single exception being a recursive call to parse function 
    // expressions and accessors), handwritten bottom-up parser. ECMAScript5 expressions serve as a good line of demarcation for handwritten bottom-
    // up parsers: any more complex than this, and you shouldn't attempt it.
    //
    // Apex has a horrific overhead in calling non-builtin instance methods, so this iterative algorithm helps keep CPU time down in Apex's very 
    // "special" runtime. Furthermore, expressions are the most frequently parsed non-lexical entity in the ECMAScript grammar (i.e. they're closest
    // to the char level -- so optimizing expression parsing reaps significant rewards.
    //
    // Also note that we directly serialize object-code instructions in the parsing pass, rather than generating an AST. This means that while our
    // object-code will not be well optimized, our startup overhead -- lexing, parsing, serializing object-code, and starting up a virtual machine
    // instance -- will be extremely low.
    
    public static final Integer LVL_COMMA      =  0;
    public static final Integer LVL_ASSIGN     =  1;
    public static final Integer LVL_TERNARY    =  2;
    public static final Integer LVL_LOGICALOR  =  3;
    public static final Integer LVL_LOGICALAND =  4;
    public static final Integer LVL_BITOR      =  5;
    public static final Integer LVL_BITXOR     =  6;
    public static final Integer LVL_BITAND     =  7;
    public static final Integer LVL_EQUALITY   =  8;
    public static final Integer LVL_RELATIONAL =  9;
    public static final Integer LVL_SHIFT      = 10;
    public static final Integer LVL_ARITH      = 11;
    public static final Integer LVL_MULT       = 12;
    public static final Integer LVL_UNARY      = 13;
    public static final Integer LVL_POSTFIX    = 14;
    // !! I've done away with the ECMAScript's silly/confusing MemberExpression grammar production and merged the syntax/sematics of CallExpression,
    // NewExpression and MemberExpression into simply CallExpr and NewExpr -- the net meaning is equivalent to that of the ECMAScript5 spec. The
    // important thing to realize is that a "new" operator may bind to up to 1 explicit CallArgs, and the binding is right-associative (innermost to
    // outermost). As soon as more CallArgs are encountered than "new" operators,for an expr that is currently at LVL_NEWOP, the expr is raised from
    // LVL_NEWOP to LVL_CALL -- and those CallArgs as well as subsequent consecutive CallArgs will resolve to a CALL rather than a CONSTRUCT.
    public static final Integer LVL_CALL       = 15;
    public static final Integer LVL_NEWOP      = 16;
    public static final Integer LVL_PRIMARY    = 17;
    
    // value types:
    public static final Integer EMPTY_VAL      =  0; // null and undefined
    public static final Integer BOOL_VAL       =  1;
    public static final Integer NUM_VAL        =  2;
    public static final Integer STR_VAL        =  3;
    public static final Integer INT32_VAL      =  4;
    public static final Integer NUM_OR_STR_VAL =  5;
    public static final Integer PRIM_VAL_MAX   =  NUM_OR_STR_VAL;
    public static final Integer OBJ_VAL        =  6;
    public static final Integer ANY_VAL        =  7;
    public static final Integer REF_VAL        =  8; 
    
    // we manually manage a stack of these in lieu of a recursive algorithm that would rely upon Apex's very slow instance method invocation:
    class ExprPart {
        Integer topLvl;
        Integer curLvl;
        Boolean noIn;
        Integer mergeType;
        
        Lexer2.Token[] assignOps;
        Instruc[] assignRefs; // tracks the ENVREF/PROPREF ops in an assignment chain
        Lexer2.Token[] unaryOps;
        Lexer2.Token[] newOps;
        Integer unusedNewOps;
        
        // the following must either be null or an ENVVAL/PROPVAL:
        Instruc dispatchRefOp;
        
        // maintains information about the expected type that this part currently resolves to (note: 1-5 are guaranteed primitive values):
        // -1 => reference (environment reference or object reference)
        //  0 => any value -- a guaranteed non-reference value; additional info about the specific datatype(s) is unavailable
        //  1 => boolean primitive
        //  2 => number primitive (int, decimal, NaN, +/-Infinity)
        //  3 => string primitive
        //  4 => int32 primitive (number primitive for which abs(x) == x and -2^31 <= x < 2^31)
        //  5 => either a number or string primitive (i.e. the result of a binary '+' op with unknown operand types)
        //  6 => object (includes the primitive wrapper objects)
        Integer valueType;
        
        // this allows anonymous function expressions to derive a quality trace name from their lexical context. for example, in the following expr:
        //     foo.bar = { baz: { qux: function () {} } }
        // the anonymous function will be able to infer the trace name: "Object.foo.bar.baz.qux"
        String[] lhsLexicalContext;
        
        // lefthand lexical reference chains are built up here (for the lefthand side of an assignment) and then, on extension via '=', passed over
        // to the righthand side of the assignment as the new part's "lhsLexicalContext". the lhsLexicalContext can be passed on though primary object-
        // literal data (adding a property name each time it's passed), and will be written into primary-data anonymous functions:
        String[] lefthandRefChain;
        
        // records the next-instruction offset (into the current part) right before we start a new part to parse a subscript expr:
        Integer subscriptStartOffset;
        
        // only relevant between CALL_ARGS start and CALL instrucs; set to true only when this call looks like a "direct call" to eval:
        Boolean evalDirectCall;
        
        // instantiated in an "extend" action for the ternary '?' operator; updated (intVal addr increment resolved) in MERGE_TERNARY_TRUE:
        Instruc.JumpOnFalse ternaryJmpToFalse;
        // instantiated in MERGE_TERNARY_TRUE and updated (intVal addr increment resolved) in MERGE_TERNARY_FALSE:
        Instruc.Jump ternaryJmpToEnd;
        // an instance of either JMPT (LogicalOr) or JMPF (LogicalAnd). shortCircuitJmp.intVal is updated twice: upon instantation to the JMPT|JMF's
        // addr offset, and later in MERGE_BIN_TERM (when merging into a LogicalOr or LogicalAnd) to the final addr increment (derived using the
        // initial intVal):
        Instruc shortCircuitJmp;
        
        // the following map is used for EXTEND_OBJ_LIT; it tracks the previously defined properties on the current object:
        // 0 => data property, 1 => getter, 2 => setter, 3 => getter + setter
        Map<String, Integer> prevObjProps;
        
        // the following 3 properties are used for MERGE_OBJ_LIT, and they are mutually exculsive (exactly 1 must be non-null for a MERGE_OBJ_LIT):
        
        // the outstanding object property name that we're waiting for the value part expr to return/merge to; this is stored on the part that
        // represents the object-literal value itself, not on the part for the value expr:
        String outstandingObjKey;
        // a property getter function:
        CodeContext.Function outstandingObjGetter;
        // a property setter function:
        CodeContext.Function outstandingObjSetter;
        
        // used for MERGE_BIN_TERM; the op-token on the left-hand expr that caused the binary extension term that's being merged:
        Lexer2.Token outstandingOpTok;
    }
    
    // setup a pool of ExprPart instances; initial pool size is 40 and we'll "stock" it in the subsequent static block:
    static final ExprPart[] PartPool = new ExprPart[40];
    // the pool is "depleted" when PartPoolTop is less than 0:
    static Integer PartPoolTop;
    // the current size of the pool is equivalent to PartPoolLmt + 1:
    static Integer PartPoolLmt;
    // the number of expr-part instances issued; this may be equal to or less than the current pool size (PartPoolLmt + 1):
    static Integer PartPoolIssued;
    static {
        for (Integer i=0; i < PartPool.size(); i++) {
            PartPool[i] = new ExprPart();
        }
        PartPoolTop = PartPool.size() - 1;
        PartPoolLmt = PartPoolTop;
        PartPoolIssued = PartPoolLmt + 1;
    }
    
    static ExprPart issuePart() {
        // if the pool has been depleted, then issue and return a new instance:
        if (PartPoolTop < 0) {
            PartPoolIssued++;
            // if we've now issued more than the pool's limit, then increase the pool size (double it):
            Integer poolSize = PartPoolLmt + 1;
            if (PartPoolIssued > poolSize) {
                PartPool.addAll(new ExprPart[poolSize]);
                PartPoolLmt += poolSize;
            }
            return new ExprPart();
        }
        return PartPool[PartPoolTop--];
    }
    
    static void returnPart(ExprPart part) {
        PartPool[++PartPoolTop] = part;
    }
    
    // 0 => add as next term in a binary-terms expr
    // 1 => () - primary.nestedExpr
    // 2 => [] - dynamic member (subscript) for NewOp or Call
    // 3 => callArgs value for the top <argv> in a NewOp or Call
    // 4 => next object-literal value expr, corresponding to an outstanding property key/name
    // 5 => next array-literal element
    // 6 => the true-branch for a ternary expr
    // 7 => the false-branch for a ternary expr
    static final Integer MERGE_BIN_TERM      = 0;
    static final Integer MERGE_NESTED        = 1;
    static final Integer MERGE_SUBSCRIPT     = 2;
    static final Integer MERGE_CALL_ARG      = 3;
    static final Integer MERGE_OBJ_LIT       = 4;
    static final Integer MERGE_ARRAY_LIT     = 5;
    static final Integer MERGE_TERNARY_TRUE  = 6;
    static final Integer MERGE_TERNARY_FALSE = 7;
    
    // action types:
    static final Integer PT_START        = 0;
    static final Integer PT_EXTEND       = 1;
    static final Integer PT_EXTEND_OBJ   = 2;
    static final Integer PT_EXTEND_ARRAY = 3;
    static final Integer PT_MERGE        = 4;
    // we need a special merge action after parsing an object literal's accessor function -- in this case we're not actually reclaiming an expr-part
    // because none was created; the accessor's function code was parsed via a recursive call and stored in outstandingObjGetter/outstandingObjSetter:
    static final Integer PT_MERGE_OBJ_ACCESSOR = 5;
    
    public static final Integer ANY_RESULT = 0;
    public static final Integer TOVAL_RESULT = 1;
    
    // in parseExpr's return value, this is the bit that indicates whether the expr is guaranteed to result in a non-Reference value or not:
    public static final Integer GUARANTEED_VALUE_BIT = 1 << 5;
    // a mask for the lower 5 lvl bits from parseExpr's return value:
    public static final Integer EXPR_LVL_MASK = 31;
    
    /* returns the bit-AND of the parsed expr's lvl (lower 5 bits) and a "is guaranteed non-reference value" 6th bit (2^5 == 32) -- 1 if the expr is
     * guaranteed to evaluate to a non-Reference value, and 0 if its result may be a Reference value (though there are no guarantees either way in
     * that case)
     * 
     * instrucs are serialized as follows (TODO: finish documenting instrucs for all expr types):
     * 
     * OrExpr:
     * <term1> JMPT[<next.offset>] POP <term2> JMPT[<next.offset>] POP <term3> <next>
     * AndExpr:
     * <term1> (JMPF[<next.offset>] POP <termN>)+ <next>
     * TernaryExpr:
     * <testExpr> JMPF[POP][<falseExpr.offset>] <trueExpr> GOTO[next.offset] <falseExpr> <next>
     */
    public static Integer parseExpr(Lexer2 lex, BlockContext hostBlock, Instruc[] instrucs, Integer startTopLvl, Boolean noIn, 
            Integer resultDirective, String[] lhsLexicalContext) {
        
        Lexer2.Token[] toks = lex.toks;
        Lexer2.Token peek;
        Integer peekType;
        
        // the top level exp-part; this will always be the bottom (left-most element) of the stack:
        ExprPart part;
        if (PartPoolTop > -1) {
            part = PartPool[PartPoolTop--];
        } else {
            part = issuePart();
        }
        part.topLvl = startTopLvl;
        part.noIn = noIn;
        part.lhsLexicalContext = lhsLexicalContext;
        part.newOps = null;
        // it's important to clear this out since it may remain from a prior part before it was replaced into the pool:
        part.shortCircuitJmp = null;
        // each entry in this stack represents an expr-part that has not yet completed; the top of the stack is the current part, and the bottom
        // holds what will become the final result product for this parseExpr call (i.e. the "root" part):
        ExprPart[] stack = new ExprPart[]{ part };
        Integer action = PT_START;
        
        Instruc ins;
        
        // when an iteration results in the start a new expr-part, then the new part's custom attributes will be set into the following:
        Integer nextPartTopLvl;
        Boolean nextPartNoIn;
        Integer nextPartMergeType;
        String[] nextPartLhsLexicalContext;
        
        Integer opLvl;
        Lexer2.Token opTok;
        Integer opTokType;
        
        Boolean strict = hostBlock.hostCode.strict;
        
        // the next thousand+ lines are contained in this do-while-true loop:
        do {
            // if we're starting a new expr part, then we know we've got to have optional prefix ops followed by a mandatory primary expr:
            if (action == PT_START) {
                // reset this flag so we don't create the part again:
                nextPartTopLvl = null;
                peek = toks[lex.next];
                peekType = peek.ttype;
                
                // first, collect any unary prefix ops:
                if (part.topLvl <= LVL_UNARY && peekType != Lexer2.KW_NEW && (Lexer2.TokenClassifications[peekType] & Lexer2.TKLASS_PREFIX) > 0) {
                    //hasPrefixOps = true;
                    part.unaryOps = new Lexer2.Token[]{};
                    do {
                        part.unaryOps.add(peek);
                        lex.next++;
                    } while ((peekType = (peek = toks[lex.next]).ttype) != Lexer2.KW_NEW && (Lexer2.TokenClassifications[peekType] & Lexer2.TKLASS_PREFIX) > 0);
                }
                
                // next, collect any "new" ops:
                if (part.topLvl <= Lexer2.KW_NEW && peekType == Lexer2.KW_NEW) {
                    //hasPrefixOps = true;
                    // immediately raise this part to lvl NEWOP:
                    part.curLvl = LVL_NEWOP;
                    part.newOps = new Lexer2.Token[]{};
                    do {
                        part.newOps.add(peek);
                        lex.next++;
                    } while ((peekType = (peek = toks[lex.next]).ttype) == Lexer2.KW_NEW);
                    part.unusedNewOps = part.newOps.size();
                } else {
                    part.curLvl = LVL_PRIMARY;
                }
                
                // check for the NEEDS_FEEDBACK token (this can happen e.g. if our last unary op from above was a '++' or '--' and the next char we're
                // looking at is a '/'; in this scenario the Lexer cannot -- on its own -- determine whether that is a regexp literal or division op);
                // we now have enough context here to disambiguate a non-comment '/' char (i.e. we know it must be a regexp literal):
                // !! note that we need not check this before the newOp/unary gathering, since there is no ambiguity there
                if (peekType == Lexer2.NEEDS_FEEDBACK) {
                    lex.scanMore(Lexer2.REGEXP_CONTEXT);
                    // scanMore will write over the NEEDS_FEEDBACK token (in this case it will become a REGEXP or throw an error):
                    peek = toks[lex.next];
                    peekType = peek.ttype;
                }
                
                // parse the primary node; we know we can consume the 1st token:
                lex.next++;
                // for an Identifier primary expr, allow any ECMAScript5 IdentifierName token that is not a keyword or future reserved word:
                if (peekType == Lexer2.IDENTIFIER || peekType == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS
                        // if we're not in strict-mode, then strict-mode reserved words also count as identifiers:
                        || !strict && peekType >= Lexer2.STRICT_RESERVED_MINIMUM) {
                    
                    String name = peek.lexeme;
                    part.valueType = REF_VAL;
                    // seed the lefthandRefChain, even in the presence of unary prefix ops, because we'll need it to disallow assignment into and
                    // prefix '++' and '--' on an eval/arguments environment reference in strict mode (see 11.4.4[2.] and 11.4.5[2.]). note that a
                    // 'new' op will convert the lefthandRefChain to a single-element list of "[[Construct]]" at the time the CONSTRUCT instruc is
                    // serialized, and a call invocation will convert lefthandRefChain to a single-element list of "[[Call]]" at the time the CALL
                    // instruc is serialized:
                    part.lefthandRefChain = new String[]{ name };
                    
                    ins = new Instruc.EnvRef(name);
                    // for now we set the identifier token type into the env ref instruc, but this may be changed to a stack offset in subsequent
                    // passes:
                    ins.intVal = peek.ttype;
                    
                    BlockContext.parsedEnvRef(hostBlock, (Instruc.EnvRef) ins);
                    
                } else if (peekType == Lexer2.KW_THIS) {
                    // non-strict mode doesn't allow the thisBinding to be a primitive inside any code context; we can use that knowledge to refine
                    // our valueType information:
                    part.valueType = strict ? ANY_VAL : OBJ_VAL;
                    part.lefthandRefChain = null;
                    ins = new Instruc.ThisRef();
                } else if ((Lexer2.TokenClassifications[peekType] & Lexer2.TKLASS_PRIMARY_DATA) > 0) {
                    part.lefthandRefChain = null;
                    if (peekType == Lexer2.STRING_LITERAL) {
                        part.valueType = STR_VAL;
                        // lexeme has already been preprocessed by the lexer to strip enclosing quote and resolve string escape sequences, etc:
                        ins = new Instruc.Push(peek.lexeme);
                    } else if (peekType == Lexer2.KW_FALSE) {
                        part.valueType = BOOL_VAL;
                        ins = new Instruc.Push(false);
                    } else if (peekType == Lexer2.KW_TRUE) {
                        part.valueType = BOOL_VAL;
                        ins = new Instruc.Push(true);
                    } else if (peekType == Lexer2.DECIMAL_NUMBER) {
                        // if this lexeme made it past the scanning phase as a decimal-number, then it's parseable by Double.valueOf.
                        // TODO: review whether a Double.valueOf parse will actually meet the ECMAScript spec (it's at the least very close):
                        Double dval = Double.valueOf(peek.lexeme);
                        // TODO: consider adding logic to detect a uint32 valueType (dval.longValue() == dval && dval >= 0 && dval < POW_2_32):
                        part.valueType = dval.intValue() == dval ? INT32_VAL : NUM_VAL;
                        ins = new Instruc.Push(dval);
                    } else if (peekType == Lexer2.HEX_NUMBER) {
                        Double dval = parseHex(peek.lexeme);
                        // TODO: consider adding logic to detect a uint32 valueType (dval.longValue() == dval && dval >= 0 && dval < POW_2_32):
                        part.valueType = dval.intValue() == dval ? INT32_VAL : NUM_VAL;
                        ins = new Instruc.Push(dval);
                    } else if (peekType == Lexer2.KW_NULL) {
                        // !! this is not flagged as a primitive, because we don't have an "any primitive" nor "null/undefined" value type class; 
                        // i.e. we don't attempt to optimize this case:
                        part.valueType = ANY_VAL;
                        ins = new Instruc.Push(NullSingleton.NUL);
                    } else if (peekType == Lexer2.REGEXP) {
                        part.valueType = OBJ_VAL;
                        // verify that the regexp flags are valid -- we allow all the Java Pattern flags, plus 'g':
                        Integer invalidFlagIndex = peek.regexpFlags.toLowerCase().indexOfAnyBut('idmsuxg');
                        if (invalidFlagIndex >= 0) {
                            throw new ParseException('RegExp has invalid flag \'' + peek.regexpFlags.mid(invalidFlagIndex, 1) + '\'', peek);
                        }
                        // TODO: throw parse error if the same flag is used more than once (15.10.4.1)...
                        
                        ins = new Instruc.RegexpLit(peek.lexeme, peek.regexpFlags);
                    }
                    
                // else, we have a "complex" primary node (i.e. nested expr, object literal, array literal, function expr, or illegal token):
                } else {
                    part.lefthandRefChain = null;
                    
                    // nested expr:
                    if (peekType == Lexer2.OPEN_PAREN) {
                        nextPartTopLvl = LVL_COMMA;
                        nextPartMergeType = MERGE_NESTED;
                        nextPartNoIn = false;
                        // if we've collected lhs assignee context for this primary node, then pass it along into the nested expr part:
                        nextPartLhsLexicalContext = part.lhsLexicalContext;
                        ins = null;
                        // !! this part will inherit the nested expr part's valueType upon its merge...
                    
                    // start of object literal:
                    } else if (peekType == Lexer2.OPEN_BRACE) {
                        // disallow a lead comma:
                        if (toks[lex.next].ttype == Lexer2.COMMA) {
                            throw new ParseException('Object literal cannot start with a lead comma', toks[lex.next]);
                        }
                        part.valueType = OBJ_VAL;
                        // start a new map of the existing object properties:
                        part.prevObjProps = new Map<String, Integer>();
                        // add the instruc manually since we'll be continue'ing to next iteration before the PT_START finishing logic:
                        ins = new Instruc.ObjectLit();
                        ins.loc = peek;
                        instrucs.add(ins);
                        
                        // here we route directly to logic that will parse either a next key-value pair (then eat up to 1 trailing comma after the
                        // MERGE_OBJECT_LIT) or a '}'; this logic is designated by its own action code, so that it can be reused for all pairs in an
                        // object-literal (including the 1st pair):
                        action = PT_EXTEND_OBJ;
                        continue;
                        
                    // start of array literal:
                    } else if (peekType == Lexer2.OPEN_BRACKET) {
                        part.valueType = OBJ_VAL;
                        // !! note that an array-literal may start with optional leading commas; each occurrence will generate an empty value slot.
                        // add the instruc manually since we'll be continue'ing to next iteration before the PT_START finishing logic:
                        ins = new Instruc.ArrayLit();
                        ins.loc = peek;
                        instrucs.add(ins);
                        
                        // here we route directly to logic that will parse leading commas (each such occurrence generating an empty value slot) and 
                        // then either a next value (then eat up to 1 trailing comma after the MERGE_ARRAY_LIT) or a terminating ']'; this logic is
                        // designated by its own action code, so that it can be reused for all value slots in an array-literal (including the 1st 
                        // slot):
                        action = PT_EXTEND_ARRAY;
                        continue;
                        
                    // function expr:
                    } else if (peekType == Lexer2.KW_FUNCTION) {
                        part.valueType = OBJ_VAL;
                        // here we must invoke a call to parse the function code; note that we already advanced past the lead "function" token, but
                        // parseFunctionCode expects to be looking at it, so we must backtrack by 1:
                        lex.next--;
                        ins = new Instruc.FuncExpr(parseFunctionCode(lex, hostBlock, CodeContext.FUNC_EXPR, part.lhsLexicalContext));
                        
                    // parse error; illegal token in primary expr:
                    } else {
                        throw new ParseException('Expected a value, array, object, or function to start an expression; got unexpected token \'' 
                                + peek.lexeme + '\'', peek);
                    }
                }
                
                // every case except that of a nested expr should have generated an instruc:
                if (ins != null) {
                    ins.loc = peek;
                    instrucs.add(ins);
                }
                
            // else if the current part is finished, then we must merge it left into the prior part:
            } else if (action == PT_MERGE) {
                // this is the new stack size; we're reducing it by 1:
                Integer stackSize = stack.size() - 1;
                // remove the old part from the stack:
                ExprPart rhsPart = stack.remove(stackSize);
                Integer mergeType = rhsPart.mergeType;
                // return the finished part to the pool for subsequent re-use (it won't be re-used and overwritten before we're done with it here):
                PartPool[++PartPoolTop] = rhsPart;
                // if we just finished the root expr-part, then we're done:
                if (stackSize == 0) {
                    // serialize a VAL after the root expression if the directives require a value and we can't otherwise guarantee the root part
                    // will resolve to a non-reference value without it:
                    if (resultDirective == TOVAL_RESULT && rhsPart.valueType == REF_VAL) {
                        mutateRefOpToVal(instrucs[instrucs.size() - 1]);
                        // the final VAL instruc will resolve to "any" value type:
                        return ANY_VAL;
                    }
                    
                    // we're done and instrucs are all serialized; return the expression's aggregate valueType:
                    return rhsPart.valueType;
                }
                
                // load the part at the new top of the stack; we'll merge the rhsPart into it:
                ExprPart lhsPart = stack[stackSize - 1];
                part = lhsPart;
                Integer lhsLvl = lhsPart.curLvl;
                
                // peek at the next token; don't consume it yet:
                peek = toks[lex.next];
                peekType = peek.ttype;
                
                if (mergeType == MERGE_BIN_TERM) {
                    Lexer2.Token binOpTok = lhsPart.outstandingOpTok;
                    // assignment logic:
                    // assign is a special case; its instruction serialization must be done not as the extensions roll in, but upon termination
                    // of an assignment chain (!! note that this event is does not indicate assignment chain termination, just termination of the
                    // current rhs part) -- and then in reverse order, with further special handling for compound assignemnt ops:
                    if (lhsLvl == LVL_ASSIGN) {
                        // the assignment's "cumulative" lhsPart now inherits the valueType and refChain from the rhs, because if we encounter a
                        // subsequent assignment op (i.e. if we're in a chain of assignments), then the current rhs will become the subsequent lhs:
                        lhsPart.valueType = rhsPart.valueType;
                        lhsPart.lefthandRefChain = rhsPart.lefthandRefChain;
                        
                        // !! note that we don't serialize the assign op yet; this is done only when the cumulative lhsPart itself is to be merged
                        // (i.e. when a subsequent comma op or expr terminator token is encountered), thus terminating the assignment chain. also
                        // note that the assign op was added into lhsPart.assignOps upon the extend action that started this rhsPart.
                        
                    } else {
                        // all binary operators, other than LVL_ASSIGN, require each rhs operand to be resolved to a non-reference value (note: this
                        // may precede other type conversions, e.g. ToNumber in the case of a mult op). in the case of LVL_ASSIGN, we defer the TOVAL
                        // instruc's (conditional) serialization until after assignment chain termination, since only the last rhs in the assignment
                        // chain must be a guaranteed value. note that we must serialize VAL before resolving the shortCircuitJmp's addr increment:
                        if (rhsPart.valueType == REF_VAL) {
                            mutateRefOpToVal(instrucs[instrucs.size() - 1]);
                        }
                        
                        // if we're merging into a LogicalOr or LogicalAnd, then the current instrucs.size() is used to derive the JMPT|JMPF's intVal
                        // addr increment for when the short circuiting condition is met. note that we don't serialize any additional binary-op
                        // instruc here:
                        if (lhsLvl == LVL_LOGICALOR || lhsLvl == LVL_LOGICALAND) {
                            // the JMPT|JMPF's addr offset was recorded into its intVal at the time it was instantated; we use that to derive its
                            // final addr increment:
                            lhsPart.shortCircuitJmp.intVal = instrucs.size() - lhsPart.shortCircuitJmp.intVal;
                            // logical And/Or doesn't necessarily yield a boolean value; it yields the value type of 1 of its 2 operands:
                            lhsPart.valueType = calcMergedValueType(lhsPart.valueType, rhsPart.valueType);

                            // !! logicalOr and logicalAnd are the rare exceptions (for binary ops) which may perform value type preprocessing
                            // (ToBool, on a copy of the lhs operand that is not to be retained on the stack) at the time of extension. They also do
                            // not perform value type preprocessing or binary op serialization in merge.
                            
                        // common-case binary op:
                        } else {
                            // COMMA BIT_OR BIT_XOR BIT_AND EQUALS NOT_EQUALS STRICT_EQUALS STRICT_NOT_EQUALS GREATER_THAN GREATER_THAN_EQUALS
                            // LESS_THAN LESS_THAN_EQUALS LEFT_SHIFT RIGHT_SHIFT URIGHT_SHIFT PLUS MINUS MULTIPLY DIVIDE MODULUS
                            // KW_IN KW_INSTANCEOF
                            Integer opType = binOpTok.ttype;
                            if (opType < Lexer2.LESS_THAN_EQUALS) {
                                if (opType < Lexer2.STRICT_EQUALS) {
                                    if (opType < Lexer2.BIT_AND) {
                                        // COMMA
                                        if (opType == Lexer2.COMMA) {
                                            // the pen operand is removed from stack while the top operand value carries forward:
                                            instrucs.add(POPPEN);
                                            lhsPart.valueType = rhsPart.valueType;
                                        // BIT_OR
                                        } else if (opType == Lexer2.BIT_OR) {
                                            serBinaryBitwise(instrucs, binOpTok, BTOR, lhsPart, rhsPart);
                                            lhsPart.valueType = INT32_VAL;
                                        // BIT_XOR
                                        } else {
                                            serBinaryBitwise(instrucs, binOpTok, BTXOR, lhsPart, rhsPart);
                                            lhsPart.valueType = INT32_VAL;
                                        }
                                    // BIT_AND
                                    } else if (opType == Lexer2.BIT_AND) {
                                        serBinaryBitwise(instrucs, binOpTok, BTAND, lhsPart, rhsPart);
                                        lhsPart.valueType = INT32_VAL;
                                    // EQUALS
                                    } else if (opType == Lexer2.EQUALS) {
                                        // Abstract equality
                                        // Equality and inequality (both abstract and strict variants) take operands of any type, so in contrast to
                                        // the other binary ops, we perform no operand type preprocessing beyond VAL:
                                        instrucs.add(new Instruc.Equals(binOpTok));
                                        lhsPart.valueType = BOOL_VAL;
                                    // NOT_EQUALS
                                    } else {
                                        // Abstract inequality
                                        instrucs.add(new Instruc.NotEquals(binOpTok));
                                        lhsPart.valueType = BOOL_VAL;
                                    }
                                } else if (opType < Lexer2.GREATER_THAN_EQUALS) {
                                    // STRICT_EQUALS
                                    if (opType == Lexer2.STRICT_EQUALS) {
                                        instrucs.add(new Instruc.StrictEquals(binOpTok));
                                        lhsPart.valueType = BOOL_VAL;
                                    // STRICT_NOT_EQUALS
                                    } else if (opType == Lexer2.STRICT_NOT_EQUALS) {
                                        instrucs.add(new Instruc.StrictNotEquals(binOpTok));
                                        lhsPart.valueType = BOOL_VAL;
                                    // GREATER_THAN
                                    } else {
                                        serRelationalCmp(instrucs, binOpTok, GT_INSTANCES, lhsPart, rhsPart);
                                        lhsPart.valueType = BOOL_VAL;    
                                    }
                                // GREATER_THAN_EQUALS
                                } else if (opType == Lexer2.GREATER_THAN_EQUALS) {
                                    serRelationalCmp(instrucs, binOpTok, GTEQ_INSTANCES, lhsPart, rhsPart);
                                    lhsPart.valueType = BOOL_VAL;
                                // LESS_THAN
                                } else {
                                    serRelationalCmp(instrucs, binOpTok, LT_INSTANCES, lhsPart, rhsPart);
                                    lhsPart.valueType = BOOL_VAL;
                                }
                            } else if (opType < Lexer2.MULTIPLY) {
                                if (opType < Lexer2.URIGHT_SHIFT) {
                                    // LESS_THAN_EQUALS
                                    if (opType == Lexer2.LESS_THAN_EQUALS) {
                                        serRelationalCmp(instrucs, binOpTok, LTEQ_INSTANCES, lhsPart, rhsPart);
                                        lhsPart.valueType = BOOL_VAL;
                                    // LEFT_SHIFT
                                    } else if (opType == Lexer2.LEFT_SHIFT) {
                                        serBitShift(instrucs, binOpTok, LSHFT, lhsPart, rhsPart);
                                        lhsPart.valueType = INT32_VAL;
                                    // RIGHT_SHIFT
                                    } else {
                                        serBitShift(instrucs, binOpTok, RSHFT, lhsPart, rhsPart);
                                        lhsPart.valueType = INT32_VAL;
                                    }
                                // URIGHT_SHIFT
                                } else if (opType == Lexer2.URIGHT_SHIFT) {
                                    serBitShift(instrucs, binOpTok, URSHFT, lhsPart, rhsPart);
                                    // The '>>>' op returns a uint32; since we don't track this type we have to record it as a number value:
                                    lhsPart.valueType = NUM_VAL;
                                // PLUS
                                } else if (opType == Lexer2.PLUS) {
                                    if (lhsPart.valueType > PRIM_VAL_MAX) {
                                        // PRIM[PEN] SWP
                                        instrucs.add(new Instruc.ToPrim(binOpTok, Instruc.NO_HINT, PEN_OP));
                                        instrucs.add(SWP);
                                    }
                                    if (rhsPart.valueType > PRIM_VAL_MAX) {
                                        // PRIM
                                        instrucs.add(new Instruc.ToPrim(binOpTok, Instruc.NO_HINT, TOP_OP));
                                    }
                                    instrucs.add(ADD);
                                    lhsPart.valueType = NUM_OR_STR_VAL;
                                // MINUS
                                } else {
                                    // lhs:
                                    if (lhsPart.valueType > PRIM_VAL_MAX) {
                                        // NUM[A][PEN] NUM[B] SWP
                                        instrucs.add(new Instruc.ToNum(binOpTok, PASS_A, PEN_OP));
                                        instrucs.add(NUM_B);
                                        instrucs.add(SWP);
                                    } else if (lhsPart.valueType != NUM_VAL) {
                                        // NUM[PEN]
                                        instrucs.add(NUM_PEN);
                                    }
                                    // rhs:
                                    if (rhsPart.valueType > PRIM_VAL_MAX) {
                                        // NUM[A] NUM[B] 
                                        instrucs.add(new Instruc.ToNum(binOpTok, PASS_A, TOP_OP));
                                        instrucs.add(NUM_B);
                                    } else if (rhsPart.valueType != NUM_VAL) {
                                        // NUM
                                        instrucs.add(NUM_TOP);
                                    }
                                    instrucs.add(SUBTRACT);
                                    lhsPart.valueType = NUM_VAL;
                                }
                            } else if (opType < Lexer2.KW_IN) {
                                // MULTIPLY
                                if (opType == Lexer2.MULTIPLY) {
                                    serMultiplicative(instrucs, binOpTok, MULTIPLY, lhsPart, rhsPart);
                                    lhsPart.valueType = NUM_VAL;
                                // DIVIDE
                                } else if (opType == Lexer2.DIVIDE) {
                                    serMultiplicative(instrucs, binOpTok, DIVIDE, lhsPart, rhsPart);
                                    lhsPart.valueType = NUM_VAL;
                                // MODULUS
                                } else {
                                    serMultiplicative(instrucs, binOpTok, MODULUS, lhsPart, rhsPart);
                                    lhsPart.valueType = NUM_VAL;
                                }
                            // KW_IN
                            } else if (opType == Lexer2.KW_IN) {
                                instrucs.add(new Instruc.InOp(binOpTok));
                                lhsPart.valueType = BOOL_VAL;
                            // KW_INSTANCEOF
                            } else {
                                instrucs.add(new Instruc.InstanceofOp(binOpTok));
                                lhsPart.valueType = BOOL_VAL;
                            }
                        }
                    }
                    // !! note that since we're not starting a new expr-part in this case, we'll fallthrough to the Next Action Dispatch (NAD)
                    // logic...
                    
                } else if (mergeType == MERGE_NESTED) {
                    // note that we never serialize VAL at the end of a nested part, since we must allow references to cross through ()'s groupings:
                    if (peekType == Lexer2.CLOSE_PAREN) {
                        lex.next++;
                        // always inherit the rhs grouped expr's valueType:
                        lhsPart.valueType = rhsPart.valueType;
                        // the host lhs part (which is currently at lvl primary) inherits the rhs grouped expr's lefthandRefChain, because ECMAScript
                        // specifies that assignments can go through grouping parenthesis around a valid lefthand side. we use the lefthandRefChain
                        // to e.g. disqualify assignments into eval/arguments in strict mode and e.g. to compose better trace names for anonymous
                        // function expressions. note that it's ok to inherit the ()'s lefthandRefChain even if it's for a non-ref value, because
                        // any syntactic restriction that acts upon lefthandRefChain will predicate the violation upon part.valueType==REF_VAL. an
                        // example of a useful inherited lefthandRefChain for a non-ref value part:
                        // (new foo).bar.baz = { qux: function () { return 1 + 1; } }
                        // ^ the function expression's inferred trace name is "[[Construct]].bar.baz.qux" thanks to the inherited lefthandRefChain,
                        // even though (new foo) results in a non-ref value (constructor calls always return a non-ref value).
                        // 
                        // transfer lefthandRefChain from the part inside the ()'s to the part that hosts the ()'s:
                        lhsPart.lefthandRefChain = rhsPart.lefthandRefChain;
                        
                        // no more instructs to serialize here; the proper instrucs will have already been serialized for this nested expr...
                    } else {
                        lex.mismatch(Lexer2.CLOSE_PAREN, 'to close parenthesis grouping expression');
                    }
                    
                } else {
                    // all of the following expr-parts must resolve to a non-reference value before the "finishing" merge instrucs (i.e. PROP,
                    // SUBSCRIPT, ARGS_ADD, CALL, CONSTRUCT, ARRAY_ADD, OBJ_PROP) are serialized and jump offsets (i.e. ternary op) are resolved:
                    if (rhsPart.valueType == REF_VAL) {
                        mutateRefOpToVal(instrucs[instrucs.size() - 1]);
                    }
                    
                    if (mergeType == MERGE_SUBSCRIPT) {
                        if (peekType == Lexer2.CLOSE_BRACKET) {
                            lex.next++;
                            
                            // additional processing to ensure that the subscript expr resolves to a string value:
                            if (rhsPart.valueType > PRIM_VAL_MAX) {
                                // STR[A] STR[B]
                                instrucs.add(new Instruc.ToStr(peek, PASS_A, TOP_OP));
                                instrucs.add(STR_B);
                            } else if (rhsPart.valueType != STR_VAL) {
                                // STR
                                instrucs.add(STR_TOP);
                            }
                            
                            // if we're building a lefthandRefChain, then attempt to resolve this subscript expr to a string property name that will be
                            // added to the chain -- obviously, we're limited to resolving very simple subscripts at compile-time:
                            if (lhsPart.lefthandRefChain != null) {
                                // the default is null, meaning we were unable to resolve this subscript instruction to a string property name -- i.e.
                                // the property is too "dynamic":
                                String propName = null;
                                // if this subscript consists of a single PUSH instruction that is string or number data, then we can resolve it to a
                                // property name for addition to our growing lefthandRefChain:
                                if (instrucs.size() - lhsPart.subscriptStartOffset == 1) {
                                    Instruc subscriptData = instrucs[instrucs.size() - 1];
                                    if (subscriptData.opCode == Instruc.OP_PUSH) {
                                        Object objVal = subscriptData.objVal;
                                        // TODO: consider using rhsPart.valueType to help determine the subscript's literal value?
                                        if (objVal == null) {
                                            propName = 'undefined';
                                        } else if (objVal === NullSingleton.NUL) {
                                            propName = 'null';
                                        } else if (objVal instanceof Double) {
                                            // TODO: whoops, I guess numbers with a decimal-point (e.g. 1.25) may be confused as multiple property names:
                                            propName = toString((Double) objVal);
                                        } else {
                                            propName = String.valueOf(objVal);
                                        }
                                    }
                                }
                                lhsPart.lefthandRefChain.add(propName);
                            }
                            
                            lhsPart.valueType = REF_VAL;
                            // use the 1-arg PropRef constructor for a dynamic property:
                            instrucs.add(new Instruc.PropRef(peek));
                        } else {
                            lex.mismatch(Lexer2.CLOSE_BRACKET, 'to close bracketed subscript expression');
                        }
                        
                    } else if (mergeType == MERGE_CALL_ARG) {
                        // advance past the expected ',' or ')':
                        lex.next++;
                        instrucs.add(ARGVADD);
                        
                        // we just completed an arg value expr; we should be looking at either a comma to continue the CallArgs, or a ')' to
                        // terminate the call args:
                        if (peekType == Lexer2.COMMA) {
                            // extra validation: check for a consecutive or trailing comma, and throw a more specific parse exception than would
                            // otherwise result by deferring the error to the next expr-part:
                            Lexer2.Token peek2 = toks[lex.next];
                            if (peek2.ttype == Lexer2.COMMA) {
                                throw new ParseException('Consecutive commas are not allowed in call arguments', peek2);
                            } else if (peek2.ttype == Lexer2.CLOSE_PAREN) {
                                throw new ParseException('Trailing commas are not allowed in call arguments', peek2);
                            }
                            
                            // setup another expr-part to parse the next call argument:
                            nextPartTopLvl = LVL_ASSIGN;
                            nextPartMergeType = mergeType;
                            nextPartNoIn = false;
                            nextPartLhsLexicalContext = null;
                            
                        // else, if looking at a ')', then we're done with these CallArgs:
                        } else if (peekType == Lexer2.CLOSE_PAREN) {
                            // issue a NEW or CALL instruc and then fallthrough to the NAD logic:
                            if (lhsLvl == LVL_NEWOP) {
                                instrucs.add(new Instruc.ConstructorDispatch(peek, lhsPart.dispatchRefOp));
                            } else {
                                instrucs.add(new Instruc.CallDispatch(peek, lhsPart.dispatchRefOp, lhsPart.evalDirectCall ? Instruc.DIRECT_CALL_EVAL_BIT : 0));
                            }
                            
                        // if we didn't actually get a ',' or ')', then we have a parse error:
                        } else {
                            lex.backMismatch(Lexer2.COMMA, 'to continue or \')\' to terminate call arguments');
                        }
                        
                    } else if (mergeType == MERGE_OBJ_LIT) {
                        // !! also see (action == PT_MERGE_OBJ_ACCESSOR) for special handling of merging accessor properties; this branch only handles
                        // the merging of key-value pairs:
                        
                        // the result of this value expr-part will reside atop the vals stack; the following instruc will pop it then put it into the
                        // PlainObject under the outstandingObjKey:
                        // TODO: peek is not really the best loc for this
                        instrucs.add(new Instruc.ObjectLitProp(peek, lhsPart.outstandingObjKey));
                        
                        // for the next token we expect either a comma or a '}'; in the case of a ',' we immediately eat it:
                        if (peekType == Lexer2.COMMA) {
                            lex.next++;
                        } else if (peekType != Lexer2.CLOSE_BRACE) {
                            lex.mismatch(Lexer2.COMMA, 'to continue or \'}\' to terminate object literal');
                        }
                        
                        // at this point, we expect to extend the object-literal by either a subsequent key-value pair (peek == comma) or termination
                        // (peek == '}'): 
                        action = PT_EXTEND_OBJ;
                        continue;
                        
                    } else if (mergeType == MERGE_ARRAY_LIT) {
                        // add the freshly parsed expr-part value to the array-literal;
                        // the result of this value expr-part will reside atop the vals stack; the following instruc will pop it then push it into
                        // the ArrayObject:
                        instrucs.add(new Instruc.ArrayLitAdd(peek));
                        
                        // for the next token we expect either a comma or a ']'; in the case of a ',' we immediately eat it:
                        if (peekType == Lexer2.COMMA) {
                            lex.next++;
                        } else if (peekType != Lexer2.CLOSE_BRACKET) {
                            lex.mismatch(Lexer2.COMMA, 'to continue or \']\' to terminate array literal');
                        }
                        
                        // at this point, we expect to extend the array-literal by either a subsequent value expr-part (peek == comma) or termination
                        // (peek == ']'): 
                        action = PT_EXTEND_ARRAY;
                        continue;
                    
                    } else if (mergeType == MERGE_TERNARY_TRUE) {
                        // serialize an unconditional Jump to the end of this ternary; note that its intVal offset can only be resolved later, in
                        // MERGE_TERNARY_FALSE:
                        lhsPart.ternaryJmpToEnd = new Instruc.Jump();
                        // record the addr of this JMP into intVal; it will be used later to derive the final addr increment:
                        lhsPart.ternaryJmpToEnd.intVal = instrucs.size();
                        instrucs.add(lhsPart.ternaryJmpToEnd);
                        // at this time, we can now resolve the intVal addr increment for the ternary conditional's JMPF. note that we recorded the
                        // JMPF's addr offset into intVal at the time it was created; we use that to derive the addr increment and then overwrite it:
                        lhsPart.ternaryJmpToFalse.intVal = instrucs.size() - lhsPart.ternaryJmpToFalse.intVal;
                        // !! now we handle this with a JMPF[POP]:
                        //// both the true and false branches must start with an instruc to pop the test-cond result off the top of the stack:
                        //instrucs.add(new Instruc.Pop());
                        
                        lhsPart.valueType = rhsPart.valueType;
                        // next, match a ':' and then setup a new part to parse the false-branch:
                        if (peekType == Lexer2.COLON) {
                            lex.next++;
                            nextPartTopLvl = LVL_ASSIGN;
                            nextPartNoIn = part.noIn;
                            nextPartMergeType = MERGE_TERNARY_FALSE;
                            nextPartLhsLexicalContext = null;
                        } else {
                            lex.mismatch(Lexer2.COLON, 'to continue ternary operator');
                        }
                        
                    } else if (mergeType == MERGE_TERNARY_FALSE) {
                        // at this time, we can now resolve the intVal addr increment for the JMP to unconditionally exit the ternary expr. note that
                        // we recorded the JMP's addr offset into intVal at the time it was created; we use that to derive the addr increment and
                        // then overwrite it:
                        lhsPart.ternaryJmpToEnd.intVal = instrucs.size() - lhsPart.ternaryJmpToEnd.intVal;
                        lhsPart.valueType = calcMergedValueType(lhsPart.valueType, rhsPart.valueType);
                    }
                }
            
            // else if we're doing a typical binary/unary/ternary op extension of the current expr-part (i.e. we're processing a next infix
            // or postfix operator of the same lvl as the current part):
            } else if (action == PT_EXTEND) {
                // !! we can reference opLvl, opTok, and opTokType, but note that lex has been advanced past the op token
                
                // upon an extend, every operator -- other than those at LVL_ASSIGN and LVL_POSTFIX -- will require a non-reference value for its
                // lefthand operand...
                
                if (opLvl == LVL_CALL || opLvl == LVL_NEWOP) {
                    // dot static-property access:
                    if (opTokType == Lexer2.DOT) {
                        // mutate a preceding ENVREF/PROPREF => ENVVAL/PROPVAL
                        if (part.valueType == REF_VAL) {
                            mutateRefOpToVal(instrucs[instrucs.size() - 1]);
                        }
                        // the dot-property op always results in a reference:
                        part.valueType = REF_VAL;
                        // peek at the next token past the '.'; we expect to be looking at an identifier|keyword:
                        peek = toks[lex.next];
                        // allow any ECMAScript5 IdentifierName as the property name:
                        if (peek.ttype == Lexer2.IDENTIFIER || peek.ttype == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS 
                                || peek.ttype >= Lexer2.KEYWORD_MINIMUM) {
                            // advance past the property name:
                            lex.next++;
                            
                            if (part.lefthandRefChain != null) {
                                part.lefthandRefChain.add(peek.lexeme);
                            }
                            // use the 2-arg PropRef constructor for a static property:
                            instrucs.add(new Instruc.PropRef(peek, peek.lexeme));
                        } else {
                            lex.mismatch(Lexer2.IDENTIFIER, 'name for property reference');
                        }
                    
                    // subscript dynamic-property access:
                    } else if (opTokType == Lexer2.OPEN_BRACKET) {
                        // mutate a preceding ENVREF/PROPREF => ENVVAL/PROPVAL
                        if (part.valueType == REF_VAL) {
                            mutateRefOpToVal(instrucs[instrucs.size() - 1]);
                        }
                        
                        // the subscript op always results in a reference:
                        part.valueType = REF_VAL;
                        // we've already advanced past the '['
                        nextPartTopLvl = LVL_COMMA;
                        nextPartMergeType = MERGE_SUBSCRIPT;
                        nextPartNoIn = false;
                        nextPartLhsLexicalContext = null;
                        // check for a premature ']'; throw a parse error if detected:
                        if (toks[lex.next].ttype == Lexer2.CLOSE_BRACKET) {
                            throw new ParseException('Subscript expression is missing', toks[lex.next]);
                        }
                        
                        part.subscriptStartOffset = instrucs.size();
                        // we don't serialize the PROPREF until merge of the subscript expr...
                    
                    // else, '(' delimits the start of call args:
                    } else {
                        // peek at the next token past the '('; we expect to be looking at a comma, ')', or the start of a call-arg expr:
                        peek = toks[lex.next];
                        peekType = peek.ttype;
                        Instruc priorOp = instrucs[instrucs.size() - 1];
                        
                        // stack starts as [... <refVal>] and ends as [... <thisVal> <funcVal> <argv>]
                        
                        // burn off a new op as necessary:
                        if (opLvl == LVL_NEWOP) {
                            // mutate a prior ENVREF => ENVVAL
                            if (priorOp.opCode == Instruc.OP_ENVREF) {
                                priorOp.opCode = Instruc.OP_ENVVAL;
                                part.dispatchRefOp = priorOp;
                            // else mutate a prior PROPREF => PROPVAL
                            } else if (priorOp.opCode == Instruc.OP_PROPREF) {
                                priorOp.opCode = Instruc.OP_PROPVAL;
                                part.dispatchRefOp = priorOp;
                            // else it must be a 'new' applied to a function expression:
                            } else {
                                part.dispatchRefOp = null;
                            }
                            // !! note that we decrement the unused new-op counter at the time we encounter the '('
                            part.unusedNewOps--;
                            // whenever we invoke a constructor we reset the lefthandRefChain to a list with the single element "[[Construct]]";
                            // note that we also replicate this behavior for 1 or more sequential 'new' ops without explicit call args:
                            part.lefthandRefChain = new String[]{ '[[Construct]]' };
                            part.evalDirectCall = false;
                        } else {
                            // detect an eval direct-call; the specification calls for special handling in the runtime's dispatch of the built-in
                            // eval function based on whether it's a direct call. if the current expr part is not a guaranteed-value and the previous
                            // instruc is an environment ref with a base name of 'eval', then we can assert that this next CALL represent an eval
                            // direct-call:
                            Instruc prevOp = instrucs[instrucs.size() - 1];
                            if (part.evalDirectCall = prevOp.opCode == Instruc.OP_ENVREF 
                                    && prevOp.intVal == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS && 'eval'.equals(prevOp.strVal)) {
                                // if a code unit contains an eval direct-call anywhere inside or it (nested any # of blocks or functions deep), then
                                // we must flag it as such. a code unit flagged in this manner cannot convert any of its local declaration to stack
                                // variables, since we cannot determine at compile-time which of its declarations may become bound to dynamic code
                                // in the eval:
                                BlockContext.parsedEvalDirectCall(hostBlock);
                            }
                            // mutate a prior ENVREF => ENVVAL[THIS]
                            if (priorOp.opCode == Instruc.OP_ENVREF) {
                                // !! setting flag FLG_PUSH_THIS on the mutated ENVVAL causes the matched environment record's (i.e. the would-be
                                // environment reference's base, if resolvable) provided this-value (if any) to be pushed to the stack before the
                                // dereferenced value. i.e. ENVVAL[THIS] pushes the first 2 values needed by a CALL to the stack, with the 3rd and
                                // final required value being the subsequent argv:
                                priorOp.opCode = Instruc.OP_ENVVAL;
                                priorOp.boolVal = Instruc.FLG_PUSH_THIS;
                                part.dispatchRefOp = priorOp;
                            // else mutate a prior PROPREF => CPY PROPVAL, or a PROPREF[D] => CPYPEN PROPVAL[D]
                            } else if (priorOp.opCode == Instruc.OP_PROPREF) {
                                // insert a CPYPEN or CPY before the PROPREF, depending on its [D] (i.e. static vs. dynamic property) flag:
                                if (priorOp.boolVal == Instruc.FLG_DYNA_PROP) {
                                    instrucs.add(instrucs.size() - 1, CPYPEN);
                                } else {
                                    instrucs.add(instrucs.size() - 1, CPY);
                                }
                                // mutate the PROPREF => PROPVAL, leaving the flags intact:
                                priorOp.opCode = Instruc.OP_PROPVAL;
                                part.dispatchRefOp = priorOp;
                            // else it must be call on a function literal (e.g. function expr immediate call) atop the stack; serialize an additional
                            // PUSH[undefined] SWP, since the thisValue is undefined, so we need to insert undefined before the function value atop
                            // the stack:
                            } else {
                                part.dispatchRefOp = null;
                                instrucs.add(PUSH_UNDEFINED);
                                instrucs.add(SWP);
                            }
                            
                            // whenever we invoke a function call we reset the lefthandRefChain to a list with the single element "[[Call]]":
                            part.lefthandRefChain = new String[]{ '[[Call]]' };
                        }
                        
                        // Note: you know what? I don't care if the spec allows custom host functions to return Reference values from a CALL -- I'm
                        // not allowing it in my scripting engine. every value returned from a CALL is now a non-reference value, which saves on
                        // superfluous type processing instrucs:
                        part.valueType = ANY_VAL;
                        instrucs.add(ARGVSTART);
                        
                        // detect and handle empty call arguments as a special case:
                        if (peekType == Lexer2.CLOSE_PAREN) {
                            // consume the ')':
                            lex.next++;
                            // immediately issue a CALL or CONSTRUCT instruc (empty args), and then fallthrough to NAD logic:
                            if (opLvl == LVL_NEWOP) {
                                instrucs.add(new Instruc.ConstructorDispatch(peek, part.dispatchRefOp));
                            } else {
                                instrucs.add(new Instruc.CallDispatch(peek, part.dispatchRefOp, part.evalDirectCall ? Instruc.DIRECT_CALL_EVAL_BIT : 0));
                            }
                        // check for an invalid leading comma:
                        } else if (peek.ttype == Lexer2.COMMA) {
                            throw new ParseException('Call arguments may not lead with a comma', peek);
                        // else, we must have non-empty call arguments (i.e. we're looking at an expr for the 1st arg value):
                        } else {
                            // setup an expr-part to start parsing the 1st call arg:
                            nextPartTopLvl = LVL_ASSIGN;
                            nextPartMergeType = MERGE_CALL_ARG;
                            nextPartNoIn = false;
                            nextPartLhsLexicalContext = null;
                        }
                    }
                
                // else if this is a binary or ternary extension:
                } else if (opLvl < LVL_UNARY) {
                    
                    part.outstandingOpTok = opTok;
                    if (opLvl == LVL_TERNARY) {
                        // the ternary test condition must be resolved first to a non-reference value, and then to a boolean value:
                        if (part.valueType == REF_VAL) {
                            mutateRefOpToVal(instrucs[instrucs.size() - 1]);
                        }
                        // ternary is interesting in that:
                        // 1. it starts an expr-part that is at a higher level than itself (lvl-assign is above lvl-ternary) -- this has the effect
                        //    that nested ternary branches will bind to the closest parent, much like how the dangling-else resolves its ambiguity:
                        // 2. the new part does not inherit the parent part's noIn modifier; it always uses false for this attribute:
                        nextPartTopLvl = LVL_ASSIGN;
                        nextPartMergeType = MERGE_TERNARY_TRUE;
                        nextPartNoIn = false;
                        nextPartLhsLexicalContext = null;
                        if (part.valueType > PRIM_VAL_MAX) {
                            // BOOL[A] BOOL[B]
                            instrucs.add(new Instruc.ToBool(opTok, PASS_A, TOP_OP));
                            instrucs.add(BOOL_B);
                        } else if (part.valueType != BOOL_VAL) {
                            // BOOL:
                            instrucs.add(BOOL_TOP);
                        }
                    } else {
                        // assignment ops expect a reference value on the lhs, so bypass value conversion in those cases:
                        if (opLvl != LVL_ASSIGN && part.valueType == REF_VAL) {
                            mutateRefOpToVal(instrucs[instrucs.size() - 1]);
                        }
                        // assuming a binary-op extension for now, we setup a new expr-part for the subsequent term - that term will 
                        // have a topLvl that's exactly 1 lvl below the current lvl:
                        nextPartTopLvl = opLvl + 1;
                        nextPartMergeType = MERGE_BIN_TERM;
                        nextPartNoIn = part.noIn;
                        nextPartLhsLexicalContext = null;
                    }
                    
                    // handle special cases; this will also catch LVL_COMMA, but the following logic will be a no-op in that case:
                    if (opLvl <= LVL_LOGICALAND) {
                        // assignment logic:
                        if (opLvl == LVL_ASSIGN) {
                            // TODO: early SyntaxError; consider deferring to a runtime ReferenceError
                            if (part.valueType != REF_VAL) {
                                throw new ParseException('Invalid left-hand side in assignment', opTok);
                            }
                            
                            // the prior instruc must be an ENVREF/PROPREF:
                            Instruc refOp = instrucs[instrucs.size() - 1];
                            // 11.13.1[4.] and 11.13.2[6.]
                            // throw an early SyntaxError if we're in strict mode and this is an attempt to assign into an environment reference of
                            // 'arguments' or 'eval':
                            if (strict && refOp.opCode == Instruc.OP_ENVREF && refOp.intVal == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS) {
                                throw new ParseException('Assignment of "' + refOp.strVal + '" is not allowed in strict mode', opTok);
                            }
                            
                            // for simple '=' assignments (e.g. not '+='), the ref chain of the lhs assignee gets inherited by the new rhs part:
                            if (opTok.ttype == Lexer2.ASSIGNMENT) {
                                nextPartLhsLexicalContext = part.lefthandRefChain;
                            // compound assignments must prepare an additional value for the corresponding binary op:
                            } else {
                                // an ENVREF should become an [ENVREF ENVVAL] sequence, where the ENVVAL is a near-clone of the ENVREF. note that
                                // ENVREF and ENVVAL have no dependencies on the stack, and they each push a single element:
                                if (refOp.opCode == Instruc.OP_ENVREF) {
                                    Instruc refVal = refOp.clone();
                                    refVal.opCode = Instruc.OP_ENVVAL;
                                    instrucs.add(refVal);
                                // a PROPREF (whether dynamic or static) will replace an object-coercible value atop the stack into a reference. for
                                // compound assignment, we need to use a [PROPREF CPYVAL] sequence, so that the stack ends up as 
                                // [... <referenceValue>, <propertyValue>]:
                                } else {
                                    instrucs.add(new Instruc.CopyDerefVal(refOp.loc));
                                }
                            }
                            
                            if (part.assignOps == null) {
                                part.assignOps = new Lexer2.Token[]{ opTok };
                                part.assignRefs = new Instruc[]{ refOp };
                            } else {
                                part.assignOps.add(opTok);
                                part.assignRefs.add(refOp);
                            }
                            
                        // LogicalOr and LogicalAnd are special cases:
                        } else if (opLvl == LVL_LOGICALOR || opLvl == LVL_LOGICALAND) {
                            // we must ensure a boolean operand, while leaving the original top value (which may not be a boolean) unmodified:
                            // CPY
                            instrucs.add(CPY);
                            if (part.valueType > PRIM_VAL_MAX) {
                                // BOOL[A] BOOL[B]
                                instrucs.add(new Instruc.ToBool(opTok, PASS_A, TOP_OP));
                                instrucs.add(BOOL_B);
                            } else if (part.valueType != BOOL_VAL) {
                                // BOOL
                                instrucs.add(BOOL_TOP);
                            }
                            
                            // note that JMPT/JMPF will do an unconditional stack pop, which will remove our CPY'd boolean value:
                            part.shortCircuitJmp = opLvl == LVL_LOGICALOR ? (Instruc) new Instruc.JumpOnTrue() : (Instruc) new Instruc.JumpOnFalse();
                            // for now we set intVal to the addr offset of the JMPT|JMPF; in the corresponding merge action for this op we'll use
                            // this to derived the addr increment (overwriting the intVal at that time):
                            part.shortCircuitJmp.intVal = instrucs.size();
                            instrucs.add(part.shortCircuitJmp);
                            // if the JMPT|JMPF is not triggered, then this POP will remove the lhs value from the stack, to be superseded by the
                            // rhs (i.e. from this next term) value:
                            instrucs.add(POP);
                            
                        } else if (opLvl == LVL_TERNARY) {
                            // store a reference to the ternary's JumpOnFalse, because we won't be able to resolve its intVal (addr increment) until
                            // we're merging the next part. note that the JMPF's unconditional POP will also remove the text expr's value:
                            part.ternaryJmpToFalse = new Instruc.JumpOnFalse();
                            // record this JMPF's addr offset; we'll later use this to derive the final addr increment value:
                            part.ternaryJmpToFalse.intVal = instrucs.size();
                            instrucs.add(part.ternaryJmpToFalse);
                        }
                    }
                
                // else we must have opLvl == LVL_POSTFIX:
                } else {
                    // TODO: early SyntaxError; consider deferring to a runtime ReferenceError
                    // postfix inc & dec require the operand to be a reference value:
                    if (part.valueType != REF_VAL) {
                        throw new ParseException('Invalid left-hand side for postfix ' + opTok.lexeme, opTok);
                    }
                    
                    // now we can assert that the prior instruc must be an ENVREF/PROPREF:
                    Instruc refOp = instrucs[instrucs.size() - 1];
                    if (strict && refOp.opCode == Instruc.OP_ENVREF && refOp.intVal == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS) {
                        throw new ParseException('Postfix ' + opTok.lexeme + ' on "' 
                                + refOp.strVal + '" is not allowed in strict mode', opTok);
                    }
                    
                    // for a postfix ++/--, after the ENVREF|PROPREF we serialize [CPYVAL NUM[A] NUM[B] FORK (INC|DEC) PUT POP POP]:
                    Instruc.Put putOp;
                    instrucs.add(new Instruc.CopyDerefVal(opTok));
                    instrucs.add(new Instruc.ToNum(opTok, PASS_A, TOP_OP));
                    instrucs.add(NUM_B);
                    instrucs.add(FORK);
                    instrucs.add(opTok.ttype == Lexer2.INCREMENT ? INC1 : DEC1);
                    instrucs.add(putOp = new Instruc.Put(opTok));
                    instrucs.add(POP);
                    instrucs.add(POP);
                    
                    // all ENVREF instrucs should record their corresponding assignment PUT, in case they're converted to a stack assignment bound to
                    // an immutable variable:
                    if (refOp.opCode == Instruc.OP_ENVREF) {
                        ((Instruc.EnvRef) refOp).putOp = putOp;
                    }
                    
                    // the postfix ops always returns a number value (but we can't quite guarantee that it's an int32):
                    part.valueType = NUM_VAL;
                }
                
            // else if we're extending an object-literal with a next key-value pair, or closing it with a terminating '}' or ','-'}':
            } else if (action == PT_EXTEND_OBJ) {
                // !! note that any legal lead comma will have been consumed by a prior MERGE_OBJ_LIT action; 
                // advance past what we expect to be either an object property name token, a "get"|"set" ident token, or a '}'
                peek = toks[lex.next++];
                peekType = peek.ttype;
                
                // in the case of any peek tokens other than '}' and ',', we expect a property key-value pair OR a property getter/setter:
                if (peekType != Lexer2.CLOSE_BRACE) {
                    // for the lead token we accept string-literals, identifiers, keywords, reserved words, decimal numbers, and hex numbers:
                    if ((Lexer2.TokenClassifications[peekType] & Lexer2.TKLASS_OBJECT_KEY) > 0) {
                        Integer lookaheadType = toks[lex.next].ttype;
                        // if the next token (after peek) is a colon, then we expect a standard property:
                        if (lookaheadType == Lexer2.COLON) {
                            // advance past the colon:
                            lex.next++;
                            // setup a subsequent parse of a value expr-part for this key-value pair:
                            nextPartTopLvl = LVL_ASSIGN;
                            nextPartMergeType = MERGE_OBJ_LIT;
                            nextPartNoIn = false;
                            part.outstandingObjGetter = null;
                            part.outstandingObjSetter = null;
                            // outstandingObjKey is a necessary attribute for Instruc.ObjectLitProp, which will be instantiated upon the merge of this
                            // new part. we allow any ECMAScript5 IdentifierName, as well as string literal values:
                            if (peek.ttype == Lexer2.IDENTIFIER || peek.ttype == Lexer2.STRING_LITERAL 
                                    || peek.ttype >= Lexer2.KEYWORD_MINIMUM || peek.ttype == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS) {
                                // note that the lexeme on a STRING_LITERAL token will have already processed escape sequences:
                                part.outstandingObjKey = peek.lexeme;
                            // we also allow decimal-number and hex-number tokens, which will be toString()'d (as per ECMAScript5 9.8.1) to resolve
                            // the property name:
                            } else {
                                // parse the hex/decimal values, then assign its toString (9.8.1) to outstandingObjKey:
                                if (peek.ttype == Lexer2.DECIMAL_NUMBER) {
                                    // ECMAScript specifies double precision for all conversions:
                                    // TODO: review whether the Double.valueOf parse will actually meet the ECMAScript spec:
                                    part.outstandingObjKey = toString(Double.valueOf(peek.lexeme));
                                } else if (peek.ttype == Lexer2.HEX_NUMBER) {
                                    // the lead "0x" will have been stripped from lexeme by the Lexer:
                                    part.outstandingObjKey = toString(parseHex(peek.lexeme));
                                }
                            }
                            
                            // update prevObjProps and check whether this data property clashes with a previous property on this same object literal
                            // (see 11.1.5):
                            Integer prevProp = part.prevObjProps.put(part.outstandingObjKey, 0);
                            if (prevProp != null) {
                                if (prevProp != 0) {
                                    throw new ParseException('Data property "' + part.outstandingObjKey 
                                            + '" clashes with previous accessor definition on object literal', peek);
                                } else if (strict) {
                                    throw new ParseException('Data property "' + part.outstandingObjKey 
                                            + '" clashes with previous data definition on object literal', peek);
                                }
                            }
                            
                            // in addition to passing a clone of this part's lhsLexicalContext over to the value expr part's (i.e. the new part's)
                            // lhsLexicalContext, add the property name:
                            if (part.lhsLexicalContext != null) {
                                nextPartLhsLexicalContext = part.lhsLexicalContext.clone();
                                nextPartLhsLexicalContext.add(part.outstandingObjKey);
                            } else {
                                nextPartLhsLexicalContext = new String[]{ 'Object', part.outstandingObjKey };
                            }
                            
                        // if the peek token was an Identifier (strictly an ECMAScript Identifier, because the only valid possibilities here are
                        // "get" and "set") and the lookahead token is an ECMAScript5 IdentifierName, StringLiteral, or NumberLiteral, (i.e. any
                        // valid object property name token) then we expect to be looking at a getter or setter declaration:
                        } else if (peekType == Lexer2.IDENTIFIER 
                                && (Lexer2.TokenClassifications[lookaheadType] & Lexer2.TKLASS_OBJECT_KEY) > 0) {
                            // back up to what we expect is a "get" or "set" identifier token:
                            lex.next--;
                            part.outstandingObjKey = null;
                            if ('get'.equals(peek.lexeme)) {
                                // !! note that we don't clone lhsLexicalContext yet:
                                part.outstandingObjGetter = parseAccessorProperty(lex, hostBlock, CodeContext.FUNC_GETTER, part.lhsLexicalContext);
                                part.outstandingObjSetter = null;
                                
                                // update prevObjProps and check whether this getter property clashes with a previous property on this same object
                                // literal (see 11.1.5):
                                String getterName = part.outstandingObjGetter.name;
                                Integer prevProp = part.prevObjProps.put(getterName, 1);
                                if (prevProp != null) {
                                    if (prevProp == 2) {
                                        part.prevObjProps.put(getterName, 3); // 3 = getter (1) + setter (2)
                                    } else if (prevProp == 1 || prevProp == 3) {
                                        throw new ParseException('Getter "' + getterName 
                                                + '" clashes with a previous getter definition on object literal', part.outstandingObjGetter.nameTok);
                                    } else {
                                        throw new ParseException('Getter "' + getterName 
                                                + '" clashes with a previous data definition on object literal', part.outstandingObjGetter.nameTok);
                                    }
                                }
                                
                            } else if ('set'.equals(peek.lexeme)) {
                                // !! note that we don't clone lhsLexicalContext yet:
                                part.outstandingObjSetter = parseAccessorProperty(lex, hostBlock, CodeContext.FUNC_SETTER, 
                                        part.lhsLexicalContext);
                                part.outstandingObjGetter = null;
                                
                                // update prevObjProps and check whether this setter property clashes with a previous property on this same object
                                // literal (see 11.1.5):
                                String setterName = part.outstandingObjSetter.name;
                                Integer prevProp = part.prevObjProps.put(setterName, 2);
                                if (prevProp != null) {
                                    if (prevProp == 1) {
                                        part.prevObjProps.put(setterName, 3); // 3 = getter (1) + setter (2)
                                    } else if (prevProp == 2 || prevProp == 3) {
                                        throw new ParseException('Setter "' + setterName 
                                                + '" clashes with a previous setter definition on object literal', part.outstandingObjSetter.nameTok);
                                    } else {
                                        throw new ParseException('Setter "' + setterName 
                                                + '" clashes with a previous data definition on object literal', part.outstandingObjSetter.nameTok);
                                    }
                                }
                            } else {
                                // advance back to where we expected a ':' token:
                                lex.next++;
                                lex.mismatch(Lexer2.COLON, 'to separate property "' + peek.lexeme + '" from its value in the object literal');
                                //lex.unexpectedToken('Expected a next property value, getter, or setter in object literal');
                            }
                            // immediately merge; in the case of a getter/setter we don't want to start a new part because the function code was
                            // already parsed via a recursive call:
                            action = PT_MERGE_OBJ_ACCESSOR;
                            continue;
                            
                        } else {
                            lex.backMismatch(Lexer2.COLON, 'to separate property "' + peek.lexeme + '" from its value in the object literal');
                        }
                    } else if (peekType == Lexer2.COMMA) {
                        throw new ParseException('Consecutive commas are not allowed in an object literal', peek);
                    } else {
                        lex.backMismatch(Lexer2.IDENTIFIER, 'name, string literal, keyword, or number as a 1st property name in the object literal');
                    }
                }
                // else we're terminating the object-literal; this is a no-op...
                
            // else if we're extending an array-literal with a next value expr, or closing it with a terminating ']':
            } else if (action == PT_EXTEND_ARRAY) {
                // parse 0 or more leading commas; each encountered comma results in an empty value slot, a.k.a an Elision, since a prior PT_MERGE of
                // type MERGE_ARRAY_LIT (from a prior element) will have already consumed a single trailing comma to use as an element separator:
                while (toks[lex.next].ttype == Lexer2.COMMA) {
                    Lexer2.Token els = toks[lex.next++];
                    // !! note that array literals are the only parseable entities which can push Elisions onto the stack:
                    ins = new Instruc.Push(Elision.Instance);
                    ins.loc = els;
                    instrucs.add(ins);
                    ins = new Instruc.ArrayLitAdd(els);
                    //ins.loc = els;
                    instrucs.add(ins);
                }
                
                // parse a terminating ']' or setup a subsequent parse of a value expr-part:
                peek = toks[lex.next];
                if (peek.ttype != Lexer2.CLOSE_BRACKET) {
                    // TODO: for now we don't carry this part's lhsLexicalContext through array elements (i.e. adding the toString of index along each
                    // stop); consider doing so...
                    
                    // setup a subsequent parse of a value expr-part to add to the current array:
                    nextPartTopLvl = LVL_ASSIGN;
                    nextPartMergeType = MERGE_ARRAY_LIT;
                    nextPartNoIn = false;
                // a ']' indicates termination of the array-literal; eat the ']' token (i.e. allow NAD logic to categorize the subsequent token as a
                // raise/merge/extend) and serialize an ARRAY_END instruc:
                } else {
                    lex.next++;
                    ins = new Instruc.ArrayLitEnd(peek);
                    //ins.loc = peek;
                    instrucs.add(ins);
                }
                
            } else if (action == PT_MERGE_OBJ_ACCESSOR) {
                ExprPart activePart = stack[stack.size() - 1];
                // add the freshly accessor to the object-literal:
                if (activePart.outstandingObjGetter != null) {
                    // this instruc will not touch the stack because it already holds the FunctionCode:
                    ins = new Instruc.ObjectLitGet(activePart.outstandingObjGetter);
                } else {
                    // this instruc will not touch the stack because it already holds the FunctionCode:
                    ins = new Instruc.ObjectLitSet(activePart.outstandingObjSetter);
                }
                
                peek = toks[lex.next];
                peekType = peek.ttype;
                ins.loc = peek;
                instrucs.add(ins);
                
                // for the next token we expect either a comma or a '}'; in the case of a ',' we immediately eat it:
                if (peekType == Lexer2.COMMA) {
                    lex.next++;
                } else if (peekType != Lexer2.CLOSE_BRACE) {
                    lex.mismatch(Lexer2.COMMA, 'to continue or \'}\' to terminate object literal');
                }
                
                // at this point, we expect to extend the object-literal by either a subsequent key-value pair (peek == comma) or termination
                // (peek == '}'): 
                action = PT_EXTEND_OBJ;
                continue;
            } // end of action processing
            
            // Starting a new expr-part:
            // if the above logic determined that we must start a new expr-part, then we do so now:
            if (nextPartTopLvl != null) {
                if (PartPoolTop > -1) {
                    part = PartPool[PartPoolTop--];
                } else {
                    part = issuePart();
                }
                stack.add(part);
                action = PT_START;
                // set key attributes:
                part.topLvl = nextPartTopLvl;
                part.noIn = nextPartNoIn;
                part.mergeType = nextPartMergeType;
                part.lhsLexicalContext = nextPartLhsLexicalContext;
                // it's important to clear this out since it may remain from a prior part before it was replaced into the pool:
                if (part.shortCircuitJmp != null) {
                    part.shortCircuitJmp = null;
                }
                // !! important: we'll bypass the NAD/raise logic when we've just started a new expr-part:
                continue;
            }
            
            // Next Action Dispatch (NAD): 
            // At this point we know we'll be setting up either a merge or an extend (possibly preceded by a raise), with special-case handling also
            // responsible for some inline instruction serialization. The following logic makes the correct determinations based on the state of the
            // current part combined with the lookahead token.
            
            // store the current part's lvl, before we go through the raise logic; we'll need this to detect and handle special cases such as
            // assign/new/unary-op serialization:
            Integer priorLvl = part.curLvl;
            
            opTok = toks[lex.next];
            // check for the NEEDS_FEEDBACK token:
            if (opTok.ttype == Lexer2.NEEDS_FEEDBACK) {
                lex.scanMore(Lexer2.DIV_CONTEXT);
                // scanMore will write over the NEEDS_FEEDBACK token; in this case, it will resolve to 1 of the 2 divide-op tokens (or throw
                // an error):
                opTok = toks[lex.next];
            }
            opTokType = opTok.ttype;
            
            opLvl = Lexer2.ExprLevelTable[opTokType];
            // handle special-cases, and further differentiate between raise/merge scenarios by revising the acting opLvl:
            // we must manually differentiate between NewOp and Call since they share common postfix ops; they will always come back as LVL_CALL
            // and we must determine whether LVL_CALL or LVL_NEWOP is actually correct in this case:
            if (priorLvl == LVL_NEWOP && opLvl == LVL_CALL) {
                // a '[' or '.' op, or a '(' in a case where we haven't burned off all new ops -- in these scenarios, we don't raise a NewOp to Call:
                if (opTokType != Lexer2.OPEN_PAREN || part.unusedNewOps > 0)
                    opLvl = LVL_NEWOP;
                // else, we fallthrough to cause a raise from NewOp to Call...
            // handle 'in' ops in the case of no-in contexts:
            } else if (part.noIn == true && opTokType == Lexer2.KW_IN || opLvl == LVL_POSTFIX && opTok.leadLineBreaks > 0) {
                // 'in' is not allowed in this context; convert to a merge action:
                opLvl = -1;
            // merge if the op exceeds this part's maximum top level:
            } else if (opLvl < part.topLvl) {
                opLvl = -1;
            }
            
            // if this is a raise or merge:
            if (opLvl < priorLvl) {
                    
                // if this is not a merge, the raise the lvl of the current lhs part:
                if (opLvl != -1) {
                    part.curLvl = opLvl;
                }
                
                // assignment logic:
                // on raise or merge of a part that was at LVL_ASSIGN (note that LVL_COMMA is the only raise possibility for a LVL_ASSIGN part), we
                // perform logic to terminate the assignment chain and then serialze the necessary instrucs (right-to-left order):
                if (priorLvl == LVL_ASSIGN && opLvl < LVL_ASSIGN) {
                    // now that we're done with this assignment chain, serialize the part's collected assignOps in reverse order:
                    Integer assignOpsTop = part.assignOps.size() - 1;
                    
                    // the current part now represents the final rhs of this terminating assignment chain (of 1 or more assign ops); we must ensure
                    // that it resolves to a non-reference value for use as the rhsVal in the subequent PUT instrucs:
                    if (part.valueType == REF_VAL) {
                        // for the final rhs, mutate a prior ENVREF/PROPREF => ENVVAL/PROPVAL
                        mutateRefOpToVal(instrucs[instrucs.size() - 1]);
                        part.valueType = ANY_VAL;
                    }
                    
                    // process the assignment chain's ops from right-to-left (since the PUT ops must execute in this order); after each iteration we
                    // update part.valueType to the chain's cumulative valueType at that point:
                    for (Integer i=assignOpsTop; i >= 0; i--) {
                        Lexer2.Token assignOp = part.assignOps[i];
                        
                        // compound assignments must serialize an additional binary op (e.g. MULT) before the assign's PUT POP (e.g. 
                        // [… <TONUM prepro> MULT PUT POP]), and perform additional logic to mutate the chain's cumulative result valueType:
                        if (assignOp.ttype != Lexer2.ASSIGNMENT) {
                            // get info about the binary op that's coupled to this compound assignment:
                            Instruc.OpInfo binOpInfo = Instruc.CompoundAssignTable[assignOp.ttype];
                            
                            // serialize preprocessing logic for the binary op (e.g. NUM for MULT). note that the ASSIGN_URIGHT_SHIFT ttype must be
                            // greater than ASSIGN_RIGHT_SHIFT and ASSIGN_LEFT_SHIFT (setup in Lexer2 static defs) for this branching logic to work:
                            if (assignOp.ttype <= Lexer2.ASSIGN_URIGHT_SHIFT) {
                                // BIT_OR, BIT_XOR, and BIT_AND all require int32 operands (lhs and rhs):
                                if (assignOp.ttype <= Lexer2.ASSIGN_BIT_AND) {
                                    // lhs is guaranteed to be ANY_VAL; serialize: INT32[A][PEN] INT32[B] SWP
                                    instrucs.add(new Instruc.ToInt32(assignOp, PASS_A, PEN_OP));
                                    instrucs.add(INT32_B);
                                    instrucs.add(SWP);
                                    // rhs:
                                    if (part.valueType != INT32_VAL) {
                                        if (part.valueType <= PRIM_VAL_MAX) {
                                            // ser: INT32
                                            instrucs.add(INT32_TOP);
                                        } else {
                                            // ser: INT32[A] INT32[B]
                                            instrucs.add(new Instruc.ToInt32(assignOp, PASS_A, TOP_OP));
                                            instrucs.add(INT32_B);
                                        }
                                    }

                                // URIGHT_SHIFT requires uint32 operands:
                                } else if (assignOp.ttype == Lexer2.ASSIGN_URIGHT_SHIFT) {
                                    // lhs is always ANY_VAL; ser: UINT32[A][PEN] UINT32[B] SWP
                                    instrucs.add(new Instruc.ToUint32(assignOp, PASS_A, PEN_OP));
                                    instrucs.add(UINT32_B);
                                    instrucs.add(SWP);
                                    // rhs; note that a signed int32 always fits in a uint32, so we can skip this step if we have an int32:
                                    if (part.valueType != INT32_VAL) {
                                        if (part.valueType <= PRIM_VAL_MAX) {
                                            // ser: UINT32
                                            instrucs.add(UINT32_TOP);
                                        } else {
                                            // ser: UINT32[A] UINT32[B]
                                            instrucs.add(new Instruc.ToUint32(assignOp, PASS_A, TOP_OP));
                                            instrucs.add(UINT32_B);
                                        }
                                    }

                                // LEFT_SHIFT and RIGHT_SHIFT require an int32 lhs and unit32 rhs:
                                } else {
                                    // lhs is always ANY_VAL; ser: INT32[A][PEN] INT32[B] SWP
                                    instrucs.add(new Instruc.ToInt32(assignOp, PASS_A, PEN_OP));
                                    instrucs.add(INT32_B);
                                    instrucs.add(SWP);
                                    // rhs; note that a signed int32 always fits in a uint32, so we can skip this step if we have an int32:
                                    if (part.valueType != INT32_VAL) {
                                        if (part.valueType <= PRIM_VAL_MAX) {
                                            // ser: UINT32
                                            instrucs.add(UINT32_TOP);
                                        } else {
                                            // ser: UINT32[A] UINT32[B]
                                            instrucs.add(new Instruc.ToUint32(assignOp, PASS_A, TOP_OP));
                                            instrucs.add(UINT32_B);
                                        }
                                    }
                                }
                                
                            // PLUS requires primitive operands (string concat vs. numeric addition is determined via type checking at runtime):
                            } else if (assignOp.ttype == Lexer2.ASSIGN_PLUS) {
                                // lhs is always ANY_VAL; ser: PRIM[PEN] SWP (note no hint is provided to ToPrim)
                                instrucs.add(new Instruc.ToPrim(assignOp, Instruc.NO_HINT, PEN_OP));
                                instrucs.add(SWP);
                                // rhs:
                                if (part.valueType > PRIM_VAL_MAX) {
                                    // ser: PRIM (note no hint is provided to ToPrim)
                                    instrucs.add(new Instruc.ToPrim(assignOp, Instruc.NO_HINT, TOP_OP));
                                }
                                
                            // MINUS, MULT, DIV, and MOD all require number operands:
                            } else {
                                // lhs is guaranteed to be ANY_VAL; serialize: NUM[A][PEN] NUM[B] SWP
                                instrucs.add(new Instruc.ToNum(assignOp, PASS_A, PEN_OP));
                                instrucs.add(NUM_B);
                                instrucs.add(SWP);
                                // rhs:
                                if (part.valueType != NUM_VAL) {
                                    if (part.valueType <= PRIM_VAL_MAX) {
                                        // ser: NUM
                                        instrucs.add(NUM_TOP);
                                    } else {
                                        // ser: NUM[A] NUM[B]
                                        instrucs.add(new Instruc.ToNum(assignOp, PASS_A, TOP_OP));
                                        instrucs.add(NUM_B);
                                    }
                                }
                            }

                            // Serialize the non-assignment binary op that's coupled to this compound assignment. Note that we can simply serialize
                            // the loc-less prototype instruc, because none of these ops will throw an error or perform a dispatch that can throw an
                            // error (the PLUS op may do an internal dispatch, but its instrucs are guaranteed not to throw or recurse):
                            instrucs.add(binOpInfo.instrucProto);
                            //ins = binOpInfo.instrucProto.clone();
                            //ins.loc = assignOp;
                            //instrucs.add(ins);
                            
                            // each compound assign op will mutate the assignment chain's cumulative valueType as we process the assignment chain from
                            // right-to-left; the full assign chain would otherwise directly inherit the valueType of the right-most rhs:
                            if (assignOp.ttype == Lexer2.ASSIGN_PLUS && part.valueType == STR_VAL) {
                                // normally a '+=' results in NUM_OR_STR_VAL, but if we know the rhs is a string then we can assert that this result
                                // must be a STR_VAL:
                                part.valueType = STR_VAL;
                            } else {
                                part.valueType = binOpInfo.resultValueType;
                            }
                        }
                        // note that simple assignments don't require operand type preprocessing logic, and don't modify the cumulative valueType...
                        
                        // the stack is now [… <lhsRef> <rhsVal>], serialize the PUT POP, which will result in [… <rhsVal>]:
                        Instruc.Put putOp = new Instruc.Put(assignOp);
                        // if the lhs ref for this assignment is an ENVREF, then record the PUT op on it (may be needed in pass2 conversions of
                        // ENVREF => STKREF):
                        if (part.assignRefs[i].opCode == Instruc.OP_ENVREF) {
                            ((Instruc.EnvRef) part.assignRefs[i]).putOp = putOp;
                        }
                        instrucs.add(putOp);
                        instrucs.add(POP);
                    }
                    
                    // clear out assignOps and assignRefs so they don't find their way back into the parts pool:
                    part.assignOps = null;
                    part.assignRefs = null;
                
                // else, we have a raise or merge where the rhs op is not an assignment op:
                } else {
                    // !! note that the order matters below -- these special-cases are not mutually exclusive, and newOps have higher precedence
                    // than unaryOps, so the former must be serialized first:
                    
                    // on raise or merge of a part that was at LVL_NEWOP:
                    if (priorLvl == LVL_NEWOP) {
                        // if we have remaining unburned new-ops, they must be serialized (in reverse order) at this time:
                        if (part.unusedNewOps > 0 && opLvl < LVL_NEWOP) {
                            Instruc innermostRefOp;
                            // special processing if the innermost 'new' operator applies to a reference:
                            if (part.valueType == REF_VAL) {
                                Instruc prevOp = instrucs[instrucs.size() - 1];
                                if (prevOp.opCode == Instruc.OP_ENVREF) {
                                    prevOp.opCode = Instruc.OP_ENVVAL;
                                    innermostRefOp = prevOp;
                                } else if (prevOp.opCode == Instruc.OP_PROPREF) {
                                    prevOp.opCode = Instruc.OP_PROPVAL;
                                    innermostRefOp = prevOp;
                                }
                            }
                            // serialize each of the part's unusedNewOps (in reverse order towards the "outer-most" new ops) as [ARGV NEW]:
                            for (Integer i=part.unusedNewOps - 1; i >= 0; i--) {
                                instrucs.add(ARGVSTART);
                                instrucs.add(new Instruc.ConstructorDispatch(part.newOps[i], innermostRefOp));
                                // if we started with a ref op (i.e. ENVVAL/PROPVAL) the we should only attach it to the innermost new:
                                if (innermostRefOp != null) {
                                    innermostRefOp = null;
                                }
                            }
                            part.valueType = ANY_VAL;
                            // this is the implicit analogue of a constructor call with explicit call args, so we must replicate the same logic as
                            // we've implemented for a PT_EXTEND on call args '(': reset the lefthandRefChain to a single element list of
                            // "[[Construct]]":
                            part.lefthandRefChain = new String[]{ '[[Construct]]' };
                        }
                        // consume the new ops so they don't find their way back into the pool:
                        part.newOps = null;
                    }
                    
                    // on raise or merge of a part -- that was at or below LVL_UNARY and has unaryOps -- to a lvl above LVL_UNARY, we serialize all
                    // unary ops that were collected prior to the primary lvl parse:
                    if (priorLvl >= LVL_UNARY && part.unaryOps != null && opLvl < LVL_UNARY) {
                        for (Integer i=part.unaryOps.size(); i >= 0; i--) {
                            Lexer2.Token unaryTok = part.unaryOps[i];
                            
                            // ++ and -- require a reference
                            if (unaryTok.ttype == Lexer2.INCREMENT || unaryTok.ttype == Lexer2.DECREMENT) {
                                if (part.valueType != REF_VAL) {
                                    throw new ParseException('Invalid right-hand side for prefix ' 
                                            + (unaryTok.ttype == Lexer2.INCREMENT ? 'increment' : 'decrement'), unaryTok);
                                }
                                // now we can assert that the prior instruc must be an ENVREF/PROPREF:
                                Instruc refOp = instrucs[instrucs.size() - 1];
                                if (strict && refOp.opCode == Instruc.OP_ENVREF && refOp.intVal == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS) {
                                    throw new ParseException('Prefix ' + (unaryTok.ttype == Lexer2.INCREMENT ? 'increment' : 'decrement') + ' on "' 
                                            + refOp.strVal + '" is not allowed in strict mode', opTok);
                                }

                                // after the ENVREF/PROPREF, we serialize [CPYVAL NUM[A] NUM[B] (INC|DEC) PUT POP]
                                Instruc.Put putOp;
                                instrucs.add(new Instruc.CopyDerefVal(unaryTok));
                                instrucs.add(new Instruc.ToNum(unaryTok, PASS_A, TOP_OP));
                                instrucs.add(NUM_B);
                                instrucs.add(unaryTok.ttype == Lexer2.INCREMENT ? INC1 : DEC1);
                                instrucs.add(putOp = new Instruc.Put(unaryTok));
                                instrucs.add(POP);
                                part.valueType = NUM_VAL;
                                if (refOp.opCode == Instruc.OP_ENVREF) {
                                    ((Instruc.EnvRef) refOp).putOp = putOp;
                                }
                            
                            // the next 3 unary ops can take a ref or non-ref operand, and handle each case differently:
                            } else if (unaryTok.ttype == Lexer2.KW_TYPEOF) {
                                if (part.valueType == REF_VAL) {
                                    // for a ref, we must branch based on whether it's resolvable:
                                    // JMPREFOK4 POP PUSH["undefined"] JMP4 CPYVAL POPPEN TYPEOF
                                    instrucs.add(JMPREFOK4);
                                    instrucs.add(POP);
                                    // push the string "undefined" and jump out past the typeof op:
                                    instrucs.add(PUSH_STR_UNDEF);
                                    instrucs.add(JMP4);
                                    instrucs.add(new Instruc.CopyDerefVal(unaryTok));
                                    instrucs.add(POPPEN);
                                }
                                instrucs.add(TYPEOF);
                                part.valueType = STR_VAL;
                            } else if (unaryTok.ttype == Lexer2.KW_DELETE) {
                                if (part.valueType == REF_VAL) {
                                    // 11.4.1 - deletion of environment references is not allowed in strict mode
                                    if (strict && instrucs[instrucs.size() - 1].opCode == Instruc.OP_ENVREF) {
                                        // && part.leftHandRefChain != null && part.leftHandRefChain.size() == 1 && !part.leftHandRefChain[0].startsWith('[[')) {
                                        throw new ParseException('Deletion of unqualified reference "' 
                                                + instrucs[instrucs.size() - 1].strVal + '" is not allowed in strict mode', unaryTok);
                                    }
                                    instrucs.add(new Instruc.DeleteBinding(unaryTok));
                                } else {
                                    // for a non-reference operand, the delete op always returns true
                                    instrucs.add(POP);
                                    instrucs.add(new Instruc.Push(true));
                                }
                                part.valueType = BOOL_VAL;
                            // the remaining unary ops will all start by deref'ing a ref operand:
                            } else {
                                if (part.valueType == REF_VAL) {
                                    Instruc refOp = instrucs[instrucs.size() - 1];
                                    if (refOp.opCode == Instruc.OP_ENVREF) {
                                        refOp.opCode = Instruc.OP_ENVVAL;
                                    } else if (refOp.opCode == Instruc.OP_PROPREF) {
                                        refOp.opCode = Instruc.OP_PROPVAL;
                                    }
                                }
                                
                                if (unaryTok.ttype == Lexer2.LOGICAL_NOT) {
                                    if (part.valueType > PRIM_VAL_MAX) {
                                        instrucs.add(new Instruc.ToBool(unaryTok, PASS_A, TOP_OP));
                                        instrucs.add(BOOL_B);
                                    } else if (part.valueType != BOOL_VAL) {
                                        instrucs.add(BOOL_TOP);
                                    }
                                    instrucs.add(LOGICAL_NOT);
                                    part.valueType = BOOL_VAL;
                                } else if (unaryTok.ttype == Lexer2.MINUS || unaryTok.ttype == Lexer2.PLUS) {
                                    if (part.valueType > PRIM_VAL_MAX) {
                                        instrucs.add(new Instruc.ToNum(unaryTok, PASS_A, TOP_OP));
                                        instrucs.add(NUM_B);
                                    } else if (part.valueType != NUM_VAL && part.valueType != INT32_VAL) {
                                        instrucs.add(NUM_TOP);
                                    }
                                    // note that a unary + is a no-op (no instrucs serialized) if the operand is known to be a num or int32 at
                                    // this time.
                                    if (unaryTok.ttype == Lexer2.MINUS) {
                                        instrucs.add(NUM_NEGATE);
                                    }
                                    // if the operand was an int32, then +/- will not change that:
                                    part.valueType = part.valueType == INT32_VAL ? INT32_VAL : NUM_VAL;
                                } else if (unaryTok.ttype == Lexer2.BIT_NOT) {
                                    if (part.valueType > PRIM_VAL_MAX) {
                                        instrucs.add(new Instruc.ToInt32(unaryTok, PASS_A, TOP_OP));
                                        instrucs.add(INT32_B);
                                    } else if (part.valueType != INT32_VAL) {
                                        instrucs.add(INT32_TOP);
                                    }
                                    instrucs.add(BIT_NOT);
                                    part.valueType = INT32_VAL;
                                } else if (unaryTok.ttype == Lexer2.KW_VOID) {
                                    // the void op is so rare that it doesn't justify its own opcode; serialize [POP PUSH_UNDEF]
                                    instrucs.add(POP);
                                    instrucs.add(PUSH_UNDEFINED);
                                    part.valueType = EMPTY_VAL;
                                } else {
                                    System.assert(false, 'Unhandled unary operator: ' + unaryTok.lexeme);
                                }
                                
                            }
                        }
                        
                        // consume the unary ops so they don't find their way back into the expr-parts pool:
                        part.unaryOps = null;
                        // if this is a merge, then the part should be raised to LVL_UNARY (e.g. "+foo"); if not a merge, then the correct curLvl
                        // will have already been set by the preceding logic:
                        if (opLvl == -1) {
                            part.curLvl = LVL_UNARY;
                        }
                    }
                }
            // a "lower" -- the opposite of a raise -- is always invalid, and (in ECMAScript5) can only occur in the case of a '[', '(', or '.'
            // following a postfix ++/-- op. in the upcoming ECMAScript6, lambda expressions (and possibly other new productions) will introduce more
            // scenarios where a "lower" rhs operator token can occur:
            } else if (opLvl > priorLvl) {
                // e.g. foo++.bar
                if (opLvl == LVL_CALL && priorLvl == LVL_POSTFIX) {
                    throw new ParseException((opTokType == Lexer2.OPEN_PAREN ? 'Call arguments' : 'Property reference') 
                            + ' cannot follow a postfix increment or decrement', opTok);
                // this should never happen; I don't think it's possible (at least not until ECMAScript6 Lambda Expressions), but I put this here to
                // aid diagnosis in case I've missed some super-special edge case:
                } else {
                    throw new ParseException('Cannot process the lvl-' + opLvl + ' operator \'' + opTok.lexeme 
                            + '\' subsequent to a lvl-' + priorLvl + ' expression part', opTok);
                }
            }
            // else, this is an extend; a no-op here...
            
            // now we can decide whether to setup a merge or extend action for the next iteration:
            if (opLvl == -1) {
                action = PT_MERGE;
            } else {
                action = PT_EXTEND;
                // advance past the opTok, since opTok has been set and can be referenced in the subsequent "extend" action:
                lex.next++;
            }
            
        } while (true);
        
        return null; // unreachable; loop may only terminate though abrupt completion
    }

    // Examines the last serialized instruc; if it's a reference type, then it is mutated into its VAL equivalent, i.e.
    // ENVREF/PROPREF => ENVVAL/PROPVAL
    // You must ensure that pass 2 has not occurred at the time of call, because this method does not handle STKREF mutations of ENVREF ops. Instrucs
    // that are not a reference type are not mutated.
    static void mutateRefOpToVal(Instruc refOp) {
        if (refOp.opCode == Instruc.OP_ENVREF) {
            refOp.opCode = Instruc.OP_ENVVAL;
        } else if (refOp.opCode == Instruc.OP_PROPREF) {
            refOp.opCode = Instruc.OP_PROPVAL;
        } else {
            System.assert(false, 'Expected an ENVREF or PROPREF opcode; got: ' + refOp.toString());
        }
    }
    
    // used to calculate the resultant valueType of operators that may result in 1 of 2 alternative values, i.e. ternary op, logical or, and
    // logical and:
    static Integer calcMergedValueType(Integer lhsValueType, Integer rhsValueType) {
        if (lhsValueType == rhsValueType) {
            return lhsValueType;
        } else if (lhsValueType == ANY_VAL || rhsValueType == ANY_VAL) {
            return ANY_VAL;
        }
        
        Boolean lhsNum = lhsValueType == NUM_VAL || lhsValueType == INT32_VAL;
        Boolean rhsNum = rhsValueType == NUM_VAL || rhsValueType == INT32_VAL;
        if (lhsNum && rhsNum) {
            return NUM_VAL;
        } else if (lhsNum || lhsValueType == STR_VAL || lhsValueType == NUM_OR_STR_VAL 
                && rhsNum || rhsValueType == STR_VAL || rhsValueType == NUM_OR_STR_VAL) {
            return NUM_OR_STR_VAL;
        }
        
        return ANY_VAL;
    }
    
    static void serBinaryBitwise(Instruc[] instrucs, Lexer2.Token binOpTok, Instruc bitwiseOpInstance, ExprPart lhsPart, ExprPart rhsPart) {
        // lhs:
        if (lhsPart.valueType > PRIM_VAL_MAX) {
            // INT32[A][PEN] INT32[B] SWP
            instrucs.add(new Instruc.ToInt32(binOpTok, PASS_A, PEN_OP));
            instrucs.add(INT32_B);
            instrucs.add(SWP);
        } else if (lhsPart.valueType != INT32_VAL) {
            // INT32[PEN]
            instrucs.add(INT32_PEN);
        }
        // rhs:
        if (rhsPart.valueType > PRIM_VAL_MAX) {
            // INT32[A] INT32[B]
            instrucs.add(new Instruc.ToInt32(binOpTok, PASS_A, TOP_OP));
            instrucs.add(INT32_B);
        } else if (rhsPart.valueType != INT32_VAL) {
            // INT32
            instrucs.add(INT32_TOP);
        }
        instrucs.add(bitwiseOpInstance);
    }
    
    // Merge-action serialization logic for relational ops (LT, LTEQ, GT, GTEQ).
    // We breakout these ops' logic into this static method; it's too complex/ugly to be repeated 4x, because of the runtime differentiation between
    // numeric comparison and lexical comparison operations. The "relOpProto" argument must be an instanceof
    // LessThan|LessThanEquals|GreaterThan|GreaterThanEquals that has the NUMERIC_RELCMP flag set (boolVal):
    static void serRelationalCmp(Instruc[] instrucs, Lexer2.Token opTok, RelCmpInstances relCmp, ExprPart lhsPart, ExprPart rhsPart) {
        // example serialization, using the LessThanEquals op, and with both lhs and rhs operands being ANY_TYPE values:
        // PRIM[NUM][PEN]
        // SWP
        // PRIM[NUM]
        // JMP2STR ; addr ++ if top & pen hold 2 string values (i.e. lexical comparison), else addr += 2 (i.e. numeric comp)
        // LTEQ[LEX][4] ; lexical relational comparison. in this scenario we must additionally jump over the two NUM instrucs, so: addr += 4 continue
        // TONUM[PEN] ; skip if we know lhs is a num/int32
        // TONUM ; skip if we know rhs is a num/int32
        // LTEQ ; numeric relational comparison
        
        // we'll bypass number-conversion (for numeric comparison) on operands that are already known to be a number type (i.e. NUM_VAL, INT32_VAL):
        Boolean lhsIsNum, rhsIsNum, 
            // both lhs and rhs operands must be strings in order to invoke the lexical comparison; if we can guarantee that at least 1 operand is a
            // non-string primitive, then we'll set this flag to true:
            bypass2StrBranch;
        
        if (lhsPart.valueType > PRIM_VAL_MAX ) {
            // PRIM[NUM][PEN] SWP
            instrucs.add(new Instruc.ToPrim(opTok, NUM_HINT, PEN_OP));
            instrucs.add(SWP);
        } else {
            if (lhsPart.valueType == NUM_VAL || lhsPart.valueType == INT32_VAL) {
                lhsIsNum = true;
                bypass2StrBranch = true;
            } else if (lhsPart.valueType == BOOL_VAL) {
                bypass2StrBranch = true;
            }
        }
        
        if (rhsPart.valueType > PRIM_VAL_MAX) {
            // PRIM[NUM]
            instrucs.add(new Instruc.ToPrim(opTok, NUM_HINT, TOP_OP));
        } else {
            if (rhsPart.valueType == NUM_VAL || rhsPart.valueType == INT32_VAL) {
                rhsIsNum = true;
                bypass2StrBranch = true;
            } else if (rhsPart.valueType == BOOL_VAL) {
                bypass2StrBranch = true;
            }
        }
        
        if (bypass2StrBranch != true) {
            // JMP2STR
            instrucs.add(JMP2STR);
            // e.g. LTEQ[LEX][<addrInc=2|3|4>]
            // The addr incrementation value depends on how many NUM ops will precede the corresponding numeric comparison op. Note that we can use
            // loc-less generic Instruc instances because these ops cannot throw an error or perform a dispatch:
            instrucs.add(lhsIsNum == true && rhsIsNum == true ? relCmp.lexicalInc2 : (lhsIsNum == true || rhsIsNum == true ? relCmp.lexicalInc3 : relCmp.lexicalInc4));
        }
        
        if (lhsIsNum != true) {
            // NUM[PEN]
            instrucs.add(NUM_PEN);
        }
        if (rhsIsNum != true) {
            // NUM
            instrucs.add(NUM_TOP);
        }
        // e.g. LTEQ -- note that there's no possibility for a dispatch or error throw from this op, so we can simply use the generic loc-less prototype:
        instrucs.add(relCmp.numeric);
    }
    
    static void serBitShift(Instruc[] instrucs, Lexer2.Token binOpTok, Instruc shiftOpInstance, ExprPart lhsPart, ExprPart rhsPart) {
        // lhs:
        if (shiftOpInstance.opCode == Instruc.OP_URSHFT) {
            // The '>>>' unsigned right shift differs from '>>' and '<<' in that both of its operands are uint32, and it returns a uint32:
            if (lhsPart.valueType > PRIM_VAL_MAX) {
                // UINT32[A][PEN] UINT32[B] SWP
                instrucs.add(new Instruc.ToUint32(binOpTok, PASS_A, PEN_OP));
                instrucs.add(UINT32_B);
                instrucs.add(SWP);
            // Note that an int32 is always a uint32, so we can bypass the conversion op when we have a known int32 operand:
            } else if (lhsPart.valueType != INT32_VAL) {
                // UINT32[PEN]
                instrucs.add(UINT32_PEN);
            }
        // The '>>' and '<<' ops take an int32 lhs operand:
        } else {
            if (lhsPart.valueType > PRIM_VAL_MAX) {
                // INT32[A][PEN] INT32[B] SWP
                instrucs.add(new Instruc.ToInt32(binOpTok, PASS_A, PEN_OP));
                instrucs.add(INT32_B);
                instrucs.add(SWP);
            } else if (lhsPart.valueType != INT32_VAL) {
                // INT32[PEN]
                instrucs.add(INT32_PEN);
            }
        }
        // rhs:
        // The rhs of '>>>', '>>', and '<<' ops should be a uint32:
        if (rhsPart.valueType > PRIM_VAL_MAX) {
            // UINT32[A] UINT32[B]
            instrucs.add(new Instruc.ToUint32(binOpTok, PASS_A, TOP_OP));
            instrucs.add(UINT32_B);
        // Note that an int32 is always a uint32, so we can bypass the conversion op when we have a known int32 operand:
        } else if (rhsPart.valueType != INT32_VAL) {
            // UINT32
            instrucs.add(UINT32_TOP);
        }
        instrucs.add(shiftOpInstance);
    }
    
    static void serMultiplicative(Instruc[] instrucs, Lexer2.Token binOpTok, Instruc multOpInstance, ExprPart lhsPart, ExprPart rhsPart) {
        // lhs:
        if (lhsPart.valueType > PRIM_VAL_MAX) {
            // NUM[A][PEN] NUM[B] SWP
            instrucs.add(new Instruc.ToNum(binOpTok, PASS_A, PEN_OP));
            instrucs.add(NUM_B);
            instrucs.add(SWP);
        } else if (lhsPart.valueType != NUM_VAL) {
            // NUM[PEN]
            instrucs.add(NUM_PEN);
        }
        // rhs:
        if (rhsPart.valueType > PRIM_VAL_MAX) {
            // NUM[A] NUM[B]
            instrucs.add(new Instruc.ToNum(binOpTok, PASS_A, TOP_OP));
            instrucs.add(NUM_B);
        } else if (rhsPart.valueType != NUM_VAL) {
            // NUM
            instrucs.add(NUM_TOP);
        }
        instrucs.add(multOpInstance);
    }

    public static Instruc JMP2STR = new Instruc.JumpOnTwoStrings();
    
    static RelCmpInstances LT_INSTANCES = new RelCmpInstances(
            new Instruc.LessThan(Instruc.NUMERIC_RELCMP, 1), 
            new Instruc.LessThan(Instruc.LEXICAL_RELCMP, 2), new Instruc.LessThan(Instruc.LEXICAL_RELCMP, 3), new Instruc.LessThan(Instruc.LEXICAL_RELCMP, 4));
    static RelCmpInstances GT_INSTANCES = new RelCmpInstances(
            new Instruc.GreaterThan(Instruc.NUMERIC_RELCMP, 1), 
            new Instruc.GreaterThan(Instruc.LEXICAL_RELCMP, 2), new Instruc.GreaterThan(Instruc.LEXICAL_RELCMP, 3), new Instruc.GreaterThan(Instruc.LEXICAL_RELCMP, 4));
    static RelCmpInstances LTEQ_INSTANCES = new RelCmpInstances(
            new Instruc.LessThanEquals(Instruc.NUMERIC_RELCMP, 1), 
            new Instruc.LessThanEquals(Instruc.LEXICAL_RELCMP, 2), new Instruc.LessThanEquals(Instruc.LEXICAL_RELCMP, 3), new Instruc.LessThanEquals(Instruc.LEXICAL_RELCMP, 4));
    static RelCmpInstances GTEQ_INSTANCES = new RelCmpInstances(
            new Instruc.GreaterThanEquals(Instruc.NUMERIC_RELCMP, 1), 
            new Instruc.GreaterThanEquals(Instruc.LEXICAL_RELCMP, 2), new Instruc.GreaterThanEquals(Instruc.LEXICAL_RELCMP, 3), new Instruc.GreaterThanEquals(Instruc.LEXICAL_RELCMP, 4));
    
    class RelCmpInstances {
        Instruc numeric;
        Instruc lexicalInc2;
        Instruc lexicalInc3;
        Instruc lexicalInc4;
        
        RelCmpInstances(Instruc numeric, Instruc lexicalInc2, Instruc lexicalInc3, Instruc lexicalInc4) {
            this.numeric = numeric;
            this.lexicalInc2 = lexicalInc2;
            this.lexicalInc3 = lexicalInc3;
            this.lexicalInc4 = lexicalInc4;
        }
    }
}