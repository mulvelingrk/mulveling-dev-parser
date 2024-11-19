/*
 * Mike Ulveling
 */
global class VirtualMachine {
    // Dispatch Mode Types:
    
    // use the "synchronous" dispatch mode when a return value is immediately required (i.e. this vm is not done processing the current instruction
    // and cannot dispatch an additional execution context at that time); this is primarily used by runtime support methods, e.g. invoking a custom
    // toString/valueOf for type conversions or an accessor get/set method by Utils.getValue/putValue
    //
    // for MFunctions, a synchronous dispatch will result in the forking of a new context & vm onto which the call can be dispatched -- this allows a
    // result to be "immediately" provided (at least from the perspective of the host/parent vm) so that the host vm's suspended instruction
    // processing can resume with the correct return value.
    //
    // for all other Callable types (e.g. instances of Function), the internal [[Call]] or [[Construct]] method is directly invoked to provide
    // an "immediate" return.
    public static final Integer DISPATCH_SYNCHRONOUS = 0;
    
    // "asynchronous" dispatch is more efficient than synchronous in the case of MFunctions, since no forking of the context/vm is required -- a new
    // execution context can simply be dispatched to the host vm. for all other Callable types, the the internal [[Call]] or [[Construct]] method
    // is invoked and its return value is written into the top-of-stack for the calling execution context; this behavior mimicks an SID_RETURN
    // instruction contained in MFunction code.
    //
    // async mode is currently used in only 2 scenarios:
    // 1. for a dispatch in direct response to a SID_CALL or SID_CONSTRUCT instruction in the vm processing loop
    // 2. on "passthrough" (i.e. TailDispatchRequest) to a different target function, for any 1 of the following native builtin wrapper functions
    //    when they're called in async mode:
    //    BoundFunction.[[Call]], BoundFunction.[[Construct]], Function.prototype.call.[[Call]], and Function.prototype.apply.[[Call]]
    public static final Integer DISPATCH_ASYNC = 1;
    
    public Context ctx;
//    public Promise[] promises = new Promise[]{};
    // index 0 (i.e. the stack's bottom) is the "root" execution context for this vm; it may be either Program.GlobalCode (i.e. a module), or the
    // subject of an MFunction synchronous dispatch, or the subject of a delegated dispatch:
    public Frame[] calls = new Frame[]{};
    // the execution context that's currently active (i.e. top of calls stack); this must be maintained by any logic that dispatches a new frame or
    // terminates the current active frame:
    public Frame active;
    
    // values stack: maintains transient state for expression calculations, but does not carry state over across statements (or throw/catch
    // boundaries) in the same frame. the stack is segmented by call frame (each active ExecContext has a segStartIndex that points to its 1st
    // available stack slot). the 0 slot always holds the result value for this vm. the types of possible values contained in the stack are as
    // follows (no other types allowed): Reference, RuntimeException, Object[] (call-args or array-literal elements, the latter of which may contain
    // Elision instances), null (ECMAScript undefined), NullSingleton.NUL (ECMAScript null), PlainObject (and its subclasses), Double (ECMAScript
    // Number; no other Apex number types are allowed), String, and Boolean.
    public Object[] stack = new Object[]{ Utils.undefined };
    
    // the currently dispatched/executing instruction:
    public Instruc op;
    
    Frame.MFunc mfuncDelegate;
    Frame.InternalCall callDelegate;
    
    // !! note that none of the constructors will automatically call exec():
    
    public VirtualMachine(Context ctx) {
        this.ctx = ctx; // module.ctx;
        ctx.vm = this;
        // inherit the current op from the parent's vm, so at least we have something for op.loc:
        this.op = ctx.vm != null ? ctx.vm.op : null;
    }
    
    // this constructor creates a vm that will execute a script module:
    public VirtualMachine(Context ctx, CodeContext.GlobalCode module) {
        this(ctx);
        // the root (i.e. global) frame:
        new Frame.Main(ctx, module);
    }
    
    // throws RuntimeException:
    global Object exec() {
        /*
        Boolean exitSuccess = false;
        // outer loop handles internally thrown runtime exceptions, feeding them back into the processing loop when necessary:
        do {
            try {
                // inner loop sequentially processes instructions from the active code segment:
                do {
                    if (active.injected != null) {
                        op = active.injected;
                        active.injected = null;
                    } else
                        op = active.segment[active.next++];
                    
                    if (op.gid == Instruc.GID_PUSH) {
                        if (op.sid == Instruc.SID_VALUE) {
                            stack.add(op.objVal);
                        } else if (op.sid == Instruc.SID_ENV_REF) {
                            // 10.3.1 Identifier Resolution
                            stack.add(Environment.getIdentifierReference(ctx, op.loc, active.lexEnv, op.strVal, active.strict));
                        } else if (op.sid == Instruc.SID_THIS_REF) {
                            stack.add(active.thisBinding);
                        } else if (op.sid == Instruc.SID_FUNC_EXPR) {
                            CodeContext.Function code = (CodeContext.Function) op.objVal;
                            if (code.name == null)
                                stack.add(new MFunction(ctx, active.lexEnv, code));
                            else {
                                MFunction mfunc = new MFunction(ctx, null, code);
                                // this allows code within the function to recursively reference itself; the self-binding is immutable/undeletable:
                                mfunc.scope = DeclarativeEnv.newInstance(ctx, active.lexEnv, code.name, mfunc, false, false);
                                stack.add(mfunc);
                            }
                        } else if (op.sid == Instruc.SID_REGEXP) {
                            // the parser will have already integrated all regexp flags -- other than 'g', which is ECMAScript specific -- into the
                            // pattern; the 'g' flag is detected spearately and passed in as a boolean flag:
                            stack.add(new RegExp(ctx, (Pattern) op.objVal, op.strVal.containsIgnoreCase('g')));
                        }
                        
                        continue;
                    // end of the active execution context:
                    } else if (op.gid == Instruc.GID_END) {
                        // if the root context is ending, then halt this vm:
                        if (active.index == 0) {
                            exitSuccess = true;
                            // note that we need not clear the stacks in this case, because the vm is done...
                        } else {
                            // clear out all stack slots pertaining to the ending frame; note that we need not transfer any value to the predecessor/
                            // caller frame for an END, because the default return value should already have been written into the caller's top stack
                            // slot:
                            for (Integer i=stack.size() - 1; i >= active.segStartIndex; i--)
                                stack.remove(i);
                            
                            // close out the ending frame  and set its predecessor as the new active frame. note it's (syntactically) guaranteed that
                            // the ending frame won't have outstanding promises at the time of an END, so we need not worry about promises cleanup:
                            calls.remove(active.index);
                            active = calls[active.index - 1];
                        }
                        continue;
                    }
                    
                    Integer top = stack.size() - 1;
                    if (op.gid == Instruc.GID_JUMP) {
                        if (op.sid == Instruc.SID_GOTO) {
                            active.next = op.intVal;
                            continue;
                        } 
                        
                        Object val;
                        // boolVal flags an unconditional pop:
                        if (op.boolVal == true)
                            val = stack.remove(top);
                        else
                            val = stack[top];
                        
                        Boolean bval = Utils.toBoolean(ctx, val);
                        if (op.sid == Instruc.SID_TRUTHY && bval || op.sid == Instruc.SID_FALSEY && !bval)
                            active.next = op.intVal;
                        
                    } else if (op.gid == Instruc.GID_TOVAL) {
                        stack[top] = Utils.getValue(ctx, stack[top]);
                        
                    } else if (op.gid == Instruc.GID_POP) {
                        if (op.sid == Instruc.SID_TOP) {
                            // intVal specifies the number of pop-top operations to perform:
                            if (op.intVal == 1)
                                stack.remove(top);
                            else {
                                Integer newTop = top - op.intVal;
                                for (Integer i=top; i > newTop; i--)
                                    stack.remove(i);
                            }
                        // else SID_PEN:
                        } else
                            stack.remove(top - 1);
                            
                    } else if (op.gid == Instruc.GID_ACCESS) {
                        Object baseValue;
                        String propNameValue;
                        Integer newTop;
                        if (op.sid == Instruc.SID_PROPERTY) {
                            baseValue = stack[newTop = top];
                            propNameValue = op.strVal;
                        // else it must be SID_SUBSCRIPT:
                        } else {
                            baseValue = stack[newTop = top - 1];
                            propNameValue = Utils.toString(ctx, stack.remove(top));
                        }
                        // here we inline the logic specified in CheckObjectCoercible, constructing a more specific TypeError message if necessary:
                        if (baseValue == Utils.undefined || baseValue == Utils.nul)
                            // the SID_PROPERTY and SID_SUBSCRIPT instrucs will have had their boolVal set to true if they're the last reference in
                            // the lefthand side to a simple assignment:
                            Utils.TypeError(ctx, 'Cannot ' + (op.boolVal == true ? 'set' : 'read') + ' property \'' + propNameValue + '\' of ' 
                                    + (baseValue == Utils.undefined ? 'undefined' : 'null'));
                            
                        stack[newTop] = new Reference(op.loc, baseValue, propNameValue, active.strict);
                        
                    } else if (op.gid == Instruc.GID_PUT) {
                        // note that the righthand value at stack[top] is guaranteed to be a non-reference value...
                          
                        // 11.13.1 -- note that our Parser early-catches the spec'd SyntaxError, and our Utils.putValue method produces the
                        // TypeErrors described in the spec's NOTE:
                        if (op.boolVal != true) {
                            // reverse flag is not set (normal scenario); use pen for the left-hand (assignee ref) and top for the right-hand value:
                            Utils.putValue(ctx, stack[top - 1], stack[top]);
                            if (op.intVal == 1) {
                                // remove the left-hand side (lhs) at pen:
                                stack.remove(top - 1);
                            } else if (op.intVal == 2) {
                                // remove the rhs and lhs:
                                stack.remove(top);
                                stack.remove(top - 1);
                            }
                        } else {
                            // reverse flag is set; use top for the lefthand (assignee ref) and pen for the righthand value:
                            Utils.putValue(ctx, stack[top], stack[top - 1]);
                            if (op.intVal == 2) {
                                // remove the lhs and rhs:
                                stack.remove(top);
                                stack.remove(top - 1);
                            } else if (op.intVal == 1) {
                                // remove the lhs at top (since this is a reversed PUT):
                                stack.remove(top);
                            }
                        }
                        
                    } else if (op.gid == Instruc.GID_BINARY) {
                        // note that assignment (i.e. PUT) is special and is not handled in this branch with the "normal" binary ops;
                        // every binary op in this branch will write its result into stack[top - 1] (i.e. "pen") and will pop off the stack top: 
                        
                        Integer pen = top - 1;
                        // equality ops
                        if (op.sid <= Instruc.SID_STRICT_NOT_EQUALS) {
                            if (op.sid == Instruc.SID_EQUALS)
                                stack[pen] = Utils.abstractEquality(ctx, stack[top], stack[pen]);
                            else if (op.sid == Instruc.SID_NOT_EQUALS)
                                stack[pen] = !Utils.abstractEquality(ctx, stack[top], stack[pen]);
                            else if (op.sid == Instruc.SID_STRICT_EQUALS)
                                stack[pen] = Utils.strictEquality(ctx, stack[top], stack[pen]);
                            // else it must be SID_STRICT_NOT_EQUALS:
                            else
                                stack[pen] = !Utils.strictEquality(ctx, stack[top], stack[pen]);
                            
                        // relational ops
                        } else if (op.sid <= Instruc.SID_LESS_THAN_EQUALS) {
                            if (op.sid == Instruc.SID_GREATER_THAN)
                                stack[pen] = Utils.abstractRelComp(ctx, stack[top], stack[pen], false) == true;
                            else if (op.sid == Instruc.SID_GREATER_THAN_EQUALS)
                                stack[pen] = Utils.abstractRelComp(ctx, stack[pen], stack[top], true) == false;
                            else if (op.sid == Instruc.SID_LESS_THAN)
                                stack[pen] = Utils.abstractRelComp(ctx, stack[pen], stack[top], true) == true;
                            // else it must be SID_LESS_THAN_EQUALS:
                            else
                                stack[pen] = Utils.abstractRelComp(ctx, stack[top], stack[pen], false) == false;
                            
                        // arithmetic ops
                        } else if (op.sid == Instruc.SID_PLUS) {
                            Object lval = stack[pen], rval = stack[top];
                            // shortcut for the most common case:
                            if (lval instanceof Double && rval instanceof Double)
                                stack[pen] = (Double) lval + (Double) rval;
                            else {
                                Object lprim = Utils.toPrimitive(ctx, lval, null);
                                Object rprim = Utils.toPrimitive(ctx, rval, null);
                                if (lprim instanceof String) {
                                    if (rprim instanceof String)
                                        stack[pen] = (String) lprim + (String) rprim;
                                    else
                                        stack[pen] = (String) lprim + Utils.toString(ctx, rprim);
                                } else if (rprim instanceof String) {
                                    stack[pen] = Utils.toString(ctx, lprim) + (String) rprim;
                                } else {
                                    stack[pen] = Utils.toNumber(ctx, lprim) + Utils.toNumber(ctx, rprim);
                                }
                            }
                            
                        } else if (op.sid == Instruc.SID_MINUS) {
                            if (stack[pen] instanceof Double && stack[top] instanceof Double)
                                stack[pen] = (Double) stack[pen] - (Double) stack[top];
                            else
                                stack[pen] = Utils.toNumber(ctx, stack[pen]) - Utils.toNumber(ctx, stack[top]);
                            
                        // multiplicative ops
                        } else if (op.sid <= Instruc.SID_MODULUS) {
                            Double leftNum = Utils.toNumber(ctx, stack[pen]);
                            Double rightNum = Utils.toNumber(ctx, stack[top]);
                            if (op.sid == Instruc.SID_MULTIPLY)
                                stack[pen] = leftNum * rightNum;
                            else if (op.sid == Instruc.SID_DIVIDE) {
                                // this is merely to keep a righthand NaN from firing the next branch (since NaN.intValue() == 0, and we don't want
                                // that here) -- the Apex '/' op actually handles NaN operands just fine as long as you don't divide-by-zero:
                                if (rightNum == Utils.NaN) {
                                    stack[pen] = Utils.NaN;
                                // special handling for divide-by-zero (may be +0 or -0):
                                } else if (rightNum.intValue() == 0) {
                                    // +Infinity/+0 = +Infinity; +Infinity/-0 = -Infinity:
                                    if (leftNum == Utils.Infinity)
                                        stack[pen] = rightNum == 0 ? Utils.Infinity : Utils.MinusInfinity;
                                    // -Infinity/+0 = -Infinity; -Infinity/-0 = +Infinity:
                                    else if (leftNum == Utils.MinusInfinity)
                                        stack[pen] = rightNum == 0 ? Utils.MinusInfinity : Utils.Infinity;
                                    // NaN, +0, or -0 divided by either +0 or -0 results in NaN:
                                    else if (leftNum == Utils.NaN || leftNum == 0 || leftNum == Utils.MinusZero)
                                        stack[pen] = Utils.NaN;
                                    // else we're diving a finite nonzero number by +0 or -0:
                                    else 
                                        stack[pen] = 
                                            leftNum > 0 && rightNum == 0 || leftNum < 0 && rightNum == Utils.MinusZero 
                                                ? Utils.Infinity : Utils.MinusInfinity;
                                // else no funny stuff; we can finally use Apex's '/' op and meet the spec:
                                } else
                                    stack[pen] = leftNum / rightNum;
                            // else SID_MODULUS
                            } else {
                                // first, catch all special cases where we return NaN:
                                if (leftNum == Utils.NaN || rightNum == Utils.NaN 
                                        || leftNum == Utils.Infinity || leftNum == Utils.MinusInfinity || rightNum.intValue() == 0)
                                    stack[pen] = Utils.NaN;
                                // dividing a finite dividend -- the only remaining possibility at this point -- by an Infinity returns the dividend:
                                else if (rightNum == Utils.Infinity || rightNum == Utils.MinusInfinity)
                                    stack[pen] = leftNum;
                                // dividing a +/-0 dividend by a finite nonzero divisor -- the only remaining possibility at this point -- also
                                // returns the dividend:
                                else if (leftNum.intValue() == 0)
                                    stack[pen] = leftNum;
                                // else, no funny stuff -- both dividend and divisor are finite and nonzero, but we still can't use Apex's Math.mod
                                // method because its sucks (it only works for Integer arguments) -- so here we roll our own logic for Double args:
                                else {
                                    Integer netSign = (leftNum < 0) == (rightNum < 0) ? 1 : -1;
                                    stack[pen] = leftNum - netSign * Math.floor(Math.abs(leftNum / rightNum)) * rightNum;
                                }
                            }
                            
                        // in, instanceof
                        } else if (op.sid <= Instruc.SID_IN) {
                            if (op.sid == Instruc.SID_INSTANCEOF) {
                                Object rval = stack[top];
                                if (rval == null || !(rval instanceof PlainObject))
                                    Utils.TypeError(ctx, 'Expecting a function in instanceof check, but got ' + Utils.toString(ctx, rval));
                                
                                stack[top] = ((PlainObject) rval).hasInstance(ctx, stack[pen]);

                            // else SID_IN
                            } else {
                                Object rval = stack[top];
                                if (rval instanceof PlainObject)
                                    return ((PlainObject) rval).hasProperty(ctx, Utils.toString(ctx, stack[pen]));
                                else {
                                    String p;
                                    try {
                                        p = Utils.toString(ctx, stack[pen]);
                                    } catch (RuntimeException e) {
                                        // since rval is a primitive, the toString(rval) logic is very simple and will not fail:
                                        Utils.TypeError(ctx, 'Cannot use \'in\' operator to search ' + Utils.toString(ctx, rval));
                                    }
                                    // since rval is a primitive, the toString(rval) logic is very simple and will not fail:
                                    Utils.TypeError(ctx, 'Cannot use \'in\' operator to search for \'' + p + '\' in ' + Utils.toString(ctx, rval));
                                }
                            }
                            
                        // bitwise { & | ^ } ops
                        } else if (op.sid <= Instruc.SID_BIT_AND) {
                            Integer lnum = Utils.toInt32(ctx, stack[pen]).intValue();
                            Integer rnum = Utils.toInt32(ctx, stack[top]).intValue();
                            if (op.sid == Instruc.SID_BIT_OR)
                                stack[pen] = Double.valueOf(lnum | rnum);
                            else if (op.sid == Instruc.SID_BIT_XOR)
                                stack[pen] = Double.valueOf(lnum ^ rnum);
                            // else SID_BIT_AND:
                            else
                                stack[pen] = Double.valueOf(lnum & rnum);
                            
                        // else it must be a bit-shift op:
                        } else {
                            if (op.sid == Instruc.SID_URIGHT_SHIFT) {
                                Long lnum = Utils.toUint32(ctx, stack[pen]).longValue();
                                Long shiftCount = Utils.toUint32(ctx, stack[top]).longValue() & 31;
                                // note that since we've already converted lnum to Uint32 (i.e. a non-neagtive value), '>>' would actually yield the
                                // same result as '>>>' below:
                                stack[pen] = Double.valueOf(lnum >>> shiftCount);
                            } else {
                                Integer lnum = Utils.toInt32(ctx, stack[pen]).intValue();
                                Long shiftCount = Utils.toUint32(ctx, stack[top]).longValue() & 31;
                                if (op.sid == Instruc.SID_LEFT_SHIFT)
                                    stack[pen] = Double.valueOf(lnum << shiftCount);
                                // else SID_RIGHT_SHIFT
                                else
                                    stack[pen] = Double.valueOf(lnum >> shiftCount);
                            }
                        }
                        
                        // the binary op result will have been written into pen, which becomes the new top; the old top must be removed:
                        stack.remove(top);
                        
                    } else if (op.gid == Instruc.GID_UNARY) {
                        // note that we test for the most common unary ops first:
                        if (op.sid == Instruc.SID_LOGICAL_NOT) {
                            stack[top] = !Utils.toBoolean(ctx, stack[top]);
                        } else if (op.sid == Instruc.SID_UNARY_MINUS) {
                            stack[top] = -Utils.toNumber(ctx, stack[top]);
                        // all 4 ops {prefix/postfix * inc/dec} are adjacent in integer id, have the lowest id values of all the GID_UNARY ops, and
                        // the prefix '--' has the largest id among them -- hence we can determine when we've got 1 of these 4 unary ops by way of a
                        // single relational operator:
                        } else if (op.sid <= Instruc.SID_PREFIX_DEC) {
                            Object ref = stack[top];
                            if (ref == null || !(ref instanceof Reference))
                                Utils.ReferenceError(ctx, 'Invalid ' 
                                        + (op.sid > Instruc.SID_POSTFIX_DEC ? 'right' : 'left') + '-hand side expression in ' 
                                        + (op.sid > Instruc.SID_POSTFIX_DEC ? 'prefix' : 'postfix') + ' \'' + op.loc.lexeme + '\' operation');
                                
                            Double oldValue = Utils.toNumber(ctx, Utils.getValue(ctx, ref));
                            // op.intVal will be +1 or -1 depending on the instruc/op type being '++' or '--'; note that an oldValue of NaN, Infinity,
                            // or -Infinity will not be changed by adding +/-1:
                            Double newValue = oldValue + op.intVal;
                            Utils.putValue(ctx, ref, newValue);
                            // prefix operators overwrite the stack top with the new value:
                            if (op.sid > Instruc.SID_POSTFIX_DEC)
                                stack[top] = newValue;
                            // postfix operators return the old value, which may have undergone type conversions (we still overwrite the stack top):
                            else
                                stack[top] = oldValue;
                        } else if (op.sid == Instruc.SID_TYPEOF) {
                            Object val = stack[top];
                            if (val instanceof Reference) {
                                Reference ref = (Reference) val;
                                if (ref.base == null) {
                                    stack[top] = 'undefined';
                                    // TODO: this continue might be dangerous if we try to insert any end-of-cycle cleanup later:
                                    continue;
                                } else
                                    val = Utils.getValue(ctx, ref);
                            }
                                
                            if (val == null)
                                stack[top] = 'undefined';
                            else if (val instanceof PlainObject) {
                                if (val instanceof Callable)
                                    stack[top] = 'function';
                                else {
                                    // TODO: detect custom host object types (e.g. sobject) and return a custom type name when necessary:
                                    stack[top] = 'object';
                                }
                            } else if (val instanceof String)
                                stack[top] = 'string';
                            else if (val instanceof Double)
                                stack[top] = 'number';
                            else if (val instanceof Boolean)
                                stack[top] = 'boolean';
                            else if (val == Utils.NUL)
                                stack[top] = 'object';
                        } else if (op.sid == Instruc.SID_UNARY_PLUS) {
                            stack[top] = Utils.toNumber(ctx, stack[top]);
                        } else if (op.sid == Instruc.SID_DELETE) {
                            if (stack[top] instanceof Reference) {
                                Reference ref = (Reference) stack[top];
                                if (ref.base == null)
                                    // if this were strict mode, the parser would've already thrown a SyntaxError for 'delete' of an unqualified ref:
                                    stack[top] = true;
                                else if (ref.base instanceof Environment)
                                    // if this were strict mode, the parser would've already thrown a SyntaxError for 'delete' of an unqualified ref:
                                    stack[top] = ((Environment) ref.base).deleteBinding(ctx, ref.name);
                                else
                                    // note that if ref.base is null or undefined, then toObject will throw a TypeError:
                                    stack[top] = Utils.toObject(ctx, ref.base).deleteProperty(ctx, ref.name, ref.strict);
                                
                            } else
                                stack[top] = true;
                        } else if (op.sid == Instruc.SID_BIT_NOT) {
                            stack[top] = ~Utils.toInt32(ctx, stack[top]).intValue();
                        } else if (op.sid == Instruc.SID_VOID) {
                            // note that the parser serializes a VAL for a 'void' op as necessary, to ensure that any potential Utils.GetValue side
                            // effects are executed as per spec:
                            stack[top] = null;
                        }
                        
                    } else if (op.gid == Instruc.GID_SWITCH) {
                        if (op.sid == Instruc.SID_SWITCH_START) {
                            // jump directly to the start of the serialized case-expressions and SWITCH_CMP instructions:
                            active.next = op.intVal;
                            
                        // else it must be SID_SWITCH_CMP:
                        } else {
                            Boolean bval = Utils.strictEquality(ctx, stack[top - 1], stack.remove(top));
                            if (bval) {
                                active.next = op.intVal;
                                stack.remove(top - 1);
                            }
                        }
                        
                    } else if (op.gid == Instruc.GID_RESULT) {
                        // pops the stack top and writes that value into the stack's bottom (i.e. the vm's return value slot). this value can be a
                        // Reference only in the case of a delegated InternalCall for a custom host function that returns a Reference (very unlikely).
                        // only Program code (i.e. global and eval code) can serialize a RESULT instruc, and it only does so following an expr-stmt.
                        // furthermore, the active frame for a Program should always be at call-index 0. an InternalCall execution context may also
                        // carry a RESULT instruc if it's for a delegated call, but in this case it will also be at call-index 0.
                        stack[0] = stack.remove(top);
                        
                    } else if (op.gid == Instruc.GID_LIST_START) {
                        if (op.sid == Instruc.SID_OBJECT_LIT)
                            stack.add(new PlainObject(ctx));
                        // else the instruc is SID_CALL_ARGS or SID_ARRAY_LIT; in both cases we use an Object[] to collect argv/elements. in the case
                        // of SID_ARRAY_LIT, the Object[] will be converted into an ArrayObject upon the terminating GID_LIST_END instruc:
                        else
                            stack.add(new Object[]{});
                        
                    } else if (op.gid == Instruc.GID_LIST_ADD) {
                        if (op.sid == Instruc.SID_CALL_ARGS) {
                            // pop the stack top and add it into the argv Object[] residing at the new stack top (i.e. the old pen):
                            ((Object[]) stack[top - 1]).add(stack.remove(top));
                        } else if (op.sid == Instruc.SID_OBJECT_LIT) {
                            PropertyDescrip newDesc = PropertyDescrip.DataAllPrivs.clone();
                            newDesc.value = stack.remove(top);
                            // the spec calls for [[DefineOwnProperty]], but in this case there's no difference from a direct write into the props map:
                            ((PlainObject) stack[top - 1]).props.put(op.strVal, newDesc);
                        } else if (op.sid == Instruc.SID_OBJECT_LIT_GETTER) {
                            PropertyDescrip newDesc = PropertyDescrip.AccessorAllPrivs.clone();
                            CodeContext.Function funcCode = (CodeContext.Function) op.objVal;
                            newDesc.getter = new MFunction(ctx, active.lexEnv, funcCode);
                            ((PlainObject) stack[top]).defineOwnProperty(ctx, funcCode.name, newDesc, false);
                        } else if (op.sid == Instruc.SID_OBJECT_LIT_SETTER) {
                            PropertyDescrip newDesc = PropertyDescrip.AccessorAllPrivs.clone();
                            CodeContext.Function funcCode = (CodeContext.Function) op.objVal;
                            newDesc.setter = new MFunction(ctx, active.lexEnv, funcCode);
                            ((PlainObject) stack[top]).defineOwnProperty(ctx, funcCode.name, newDesc, false);
                        // else this must be SID_ARRAY_LIT:
                        } else {
                            // remove the stack top (it must be either an Elision or a valid ECMAScript value) and append it to the growing collection
                            // of array literal elements:
                            ((Object[]) stack[top - 1]).add(stack.remove(top));
                        }
                        
                    } else if (op.gid == Instruc.GID_LIST_END) {
                        if (op.sid == Instruc.SID_CALL_ARGS) {
                            // the stack should start out looking like this: [ ... <funcRef>, <funcVal>, <argv> ]; it shall end up looking like this:
                            // [ ... undefined ], where the top slot (with a value of undefined) will receive the call's return value, if any:
                            Object[] argv = (Object[]) stack.remove(top);
                            Object funcVal = stack.remove(top - 1);
                            
                            // 10.4.3
                            // don't remove this position from the stack; it will receive the return value:
                            Object funcRef = stack[top - 2];
                            Object thisArg;
                            if (funcRef != null && funcRef instanceof Reference) {
                                Object refBase = ((Reference) funcRef).base;
                                if (refBase instanceof Environment)
                                    thisArg = ((Environment) refBase).implicitThisValue(ctx);
                                else
                                    thisArg = refBase;
                            }
                            
                            // set async dispatch mode; the op's intVal is an optional bitfield, set by the parser, that may flag this call as either
                            // a Tail Call Elimination candidate or a direct call to eval. for MFunctions, dispatchCall will write the default return
                            // value of "undefined" into the caller's top-of-stack:
                            VirtualMachine.dispatchCall(ctx, DISPATCH_ASYNC, op.intVal, funcVal, thisArg, argv);
                            
                        } else if (op.sid == Instruc.SID_CONSTRUCT) {
                            // the stack should start out looking like this: [ ... <funcVal>, <argv> ]; it shall end up looking like this:
                            // [ ... <funcVal> ], where the top slot will synchronously or asynchronously receive the constructor's return value:
                            Object[] argv = (Object[]) stack.remove(top);
                            // don't remove this position from the stack; it will receive the return value:
                            Object funcVal = stack.remove(top - 1);
                            // for MFunctions, dispatchConstruct will write the default return (i.e. the new object thisBinding) into the caller's
                            // top-of-stack:
                            VirtualMachine.dispatchConstruct(ctx, DISPATCH_ASYNC, funcVal, argv);
                            
                        } else if (op.sid == Instruc.SID_ARRAY_LIT) {
                            // the array elements will have been collected into an Object[] atop the stack, and it may contain Elision values -- now
                            // we'll convert the Object[] into an ArrayObject, with a "hole" for each Elision:
                            stack[top] = new ArrayObject(ctx, (Object[]) stack[top]);
                        }
                        // SID_OBJECT_LIT is a no-op for GID_LIST_END...
                    
                    } else if (op.gid == Instruc.GID_ABRUPT_COMP) {
                        Integer ptop = promises.size() - 1;
                        if (op.sid == Instruc.SID_RETURN) {
                            // stack top at the time of a RETURN op is a guaranteed value:
                            Object val = stack[top];
                            // if there's no outstanding promises, or if promise handling didn't cancel the default action:
                            if (ptop < 0 || promises[ptop].handleAbruptCompletion(ctx, (Instruc.AbruptCompletion) op, val) != false) {
                                // this frame must be function code (since only function code can contain RETURN instrucs), and this if its call-index
                                // is 0 then it must have resulted from either a synchronous dispatch or a delegated dispatch; in these cases we write
                                // the return value into the stack bottom; this parallels the behavior of a RESULT instruc in global/eval code, except
                                // that in this case we need not pop the stack because the vm will be finished immediately following this instruction:
                                if (active.index == 0) {
                                    // constructors will ignore the supplied return value -- instead deferring to their default return, i.e. their
                                    // thisBinding -- if the return value was not an object. see 13.2.2[8.][9.][10.]:
                                    if (!active.isConstruct || (val != null && val instanceof PlainObject))
                                        stack[0] = val;
                                    
                                    exitSuccess = true;
                                    // note that we don't clear the stack in this case becasue the vm is done...
                                    
                                // else if the call index is not 0, then we're simply returning the result into the calling exec context's return slot:
                                } else {
                                    Frame returningFrame = calls.remove(active.index);
                                    // set the new active frame:
                                    active = calls[returningFrame.index - 1];
                                    // clear the stack of all slots pertaining to the returning frame:
                                    Integer i=stack.size() - 1;
                                    for (; i >= returningFrame.segStartIndex; i--)
                                        stack.remove(i);
                                    
                                    // constructors will ignore the supplied return value -- instead deferring to their default return, i.e. their
                                    // thisBinding -- if the return value was not an object. see 13.2.2[8.][9.][10.]:
                                    if (!returningFrame.isConstruct || (val != null && val instanceof PlainObject))
                                        // i should now point at the new top-of-stack slot, which will accept the return value:
                                        stack[i] = val;
                                }
                            }
                            
                        } else if (op.sid == Instruc.SID_BREAK || op.sid == Instruc.SID_CONTINUE) {
                            // if there's no outstanding promises, or if promise handling didn't cancel the default action:
                            if (ptop < 0 || promises[ptop].handleAbruptCompletion(ctx, (Instruc.AbruptCompletion) op, null) != false)
                                // jump to the segment offset specified by the break/continue op:
                                active.next = op.intVal;
                            
                        } else if (op.sid == Instruc.SID_THROW) {
                            // a throw op may originate from 1 of 3 places:
                            // 1. a throw statement in the source code -- in this case, the top of the stack must be a valid ECMAScript value (i.e.
                            //    not an instanceof RuntimeException)
                            // 2. an injected throw as the result of a caught RuntimeException just curried from a child vm -- in this case, the top
                            //    of the stack must be that caught RuntimeException instance
                            // 3. an injected throw as the result of the end of a finally clause that is re-throwing a deferred throw from a
                            //    preceding clause -- in this case, the top of the stack must be the deferred RuntimeException instance
                            RuntimeException runtimeErr;
                            Object tval = stack[top];
                            // if the value atop the stack is not a RuntimeException, then we have case 1. from above -- wrap it in a
                            // RuntimeException object, as TryPromise.handleAbruptCompletion expects this type of value:
                            if (tval != null && tval instanceof RuntimeException)
                                runtimeErr = (RuntimeException) tval;
                            else
                                runtimeErr = new RuntimeException(ctx, tval);
                            
                            // a return value of false from handleAbruptCompletion means "cancel default behavior":
                            if (ptop < 0 || promises[ptop].handleAbruptCompletion(ctx, (Instruc.AbruptCompletion) op, runtimeErr) != false) {
                                // setting lastHandledBy to the current ctx will cause this vm to halt and throw out the exception:
                                runtimeErr.lastHandledBy = ctx;
                                throw runtimeErr;
                            }
                            // else, we had a TryCatch promise that successfully caught or deferred (via finally clause) the throw; in this case the
                            // handleAbruptCompletion call is guaranteed to have cleared the calls stack up to the (not including) the handling frame,
                            // updated this vm's activeFrame to the handling frame, and cleared the values stack up to (and including) the
                            // handlingFrame's segStartIndex (none of its stack state may carry forward from a throw stmt), so this is a no-op here for
                            // the vm...
                        }
                    } else if (op.gid == Instruc.GID_COPY) {
                        if (op.sid == Instruc.SID_PEN) {
                            Object topVal = stack[top];
                            // the boolVal flag dictates whether we should also dereference the copy:
                            stack[top] = op.boolVal ? Utils.getValue(ctx, stack[top - 1]) : stack[top - 1];
                            stack.add(topVal);
                        // else it must be SID_TOP:
                        } else
                            // the boolVal flag dictates whether we should also dereference the copy:
                            stack.add(op.boolVal ? Utils.getValue(ctx, stack[top]) : stack[top]);
                        
                    } else if (op.gid == Instruc.GID_TRY) {
                        if (op.sid == Instruc.SID_TRY_START)
                            new Promise.TryPromise(ctx, (Instruc.TryStart) op);
                        else if (op.sid == Instruc.SID_TRY_FINALLY)
                            promises[promises.size() - 1].onTryFinally();
                        // else it must be SID_TRY_END, i.e. a natural completion:
                        else
                            promises[promises.size() - 1].onNaturalCompletion(ctx);
                        
                    } else if (op.gid == Instruc.GID_ENUM) {
                        if (op.sid == Instruc.SID_ENUM_START) {
                            Object enumSubject = stack.remove(top);
                            if (enumSubject == null || enumSubject == Utils.NUL)
                                // if we have for-in on null or undefined, then this is effectively a no-op; immediately jump past the loop's end:
                                active.next = op.intVal;
                            else
                                // else, we must instantiate the context necessary to enumerate properties on the toObject of the subject value:
                                new Promise.EnumPromise(ctx, (Instruc.EnumStart) op, Utils.toObject(ctx, enumSubject));
                        // else, it must be SID_ENUM_NEXT:
                        } else {
                            // we expect the relevant EnumPromise atop promises:
                            Promise.EnumPromise enumCtx = (Promise.EnumPromise) promises[promises.size() - 1];
                            Boolean foundNext = false;
                            while (!foundNext && enumCtx.next < enumCtx.enumList.size()) {
                                String p = enumCtx.enumList[enumCtx.next++];
                                PlainObject owner = enumCtx.nameToOwner.get(p);
                                PropertyDescrip ownDesc = owner.getOwnProperty(ctx, p);
                                // if this property has been deleted or changed to non-enumerable over the course of previous ENUM_NEXT iterations,
                                // then skip it and immediately continue on to the next property:
                                if (ownDesc == null || !ownDesc.enumerable)
                                    continue;
                                // else we got our next property; assign it into the lefthand ref and then allow the vm to process the body stmt:
                                else {
                                    // push the next property -- a string value -- atop the stack:
                                    stack.add(p);
                                    foundNext = true;
                                }
                            }
                            // check whether we hit the end of this for-in loop:
                            if (!foundNext) {
                                // we've gone through all enumerable properties; tear down the promise and jump past the end of the for-in loop:
                                enumCtx.onNaturalCompletion(ctx);
                                active.next = op.intVal;
                            }
                            // else, fallthrough: the vm has incremented active.next to point at the body stmt instruc for the next vm cycle:
                        }
                        
                    } else if (op.gid == Instruc.GID_WITH) {
                        if (op.sid == Instruc.SID_WITH_START) {
                            new Promise.WithPromise(ctx, (Instruc.WithStart) op, Utils.toObject(ctx, stack.remove(top)));
                        // else it must be SID_WITH_END:
                        } else
                            promises[promises.size() - 1].onNaturalCompletion(ctx);
                        
                    } else {
                        throw new InternalException('Unimplemented operator ' + op + '; gid=' + op.gid + ', sid=' + op.sid + '');
                    }
                    
                } while (!exitSuccess);
                
            // runtime exception currying:
            } catch (RuntimeException toCurry) {
                // each Apex-thrown runtime exception gets 1 chance for its host vm's active promises to handle it before it's flagged as "handled"
                // by this context; when we catch an exception, already handled by this context, then we must throw it out to the parent context's
                // vm, or to client code if this is the "root" context:
                if (toCurry.lastHandledBy == ctx) {
                    // this vm is toast...
                    // if we have a parent context, then we'll be currying the exception to the parent's vm;
                    // else, we're already at the top context/vm and thus have nowhere left to curry this runtime exception -- our subsequent throw
                    // won't get caught by another vm so therefore it must end up in client code...
                    throw toCurry;
                    
                // else, this exception either originated from native Apex code or it was curried from a child vm; give this vm's active promises a
                // chance to handle it before we flag it as throwOut=true:
                } else {
                    // inject this back into this vm as a THROW op, to give the next TryPromise in the promises stack a shot at handling it; if not
                    // handled then it'll be wrapped in a RuntimeException and thrown out:
                    Instruc.ThrowStmt throwOp = new Instruc.ThrowStmt();
                    // note how this injection works nicely even for NativeFunc frames:
                    active.injected = throwOp;
                    // the injected THROW should inherit the currently executing op's source code location
                    // TODO: is this necessary?
                    throwOp.loc = op.loc;
                    // !! this is one of the few times we'll put a RuntimeException instance onto the stack, in addition to the below catch clause and
                    // TryPromise.onNaturalCompletion with a deferred throw event:
                    stack.add(toCurry);
                }
            } catch (Exception nativeThrown) {
                // inject this back into this vm as a THROW op, to give the next TryPromise in the promises stack a shot at handling it; if not
                // handled then it'll be wrapped in a RuntimeException and thrown out:
                Instruc.ThrowStmt throwOp = new Instruc.ThrowStmt();
                active.injected = throwOp;
                // the injected THROW should inherit the currently executing op's source code location:
                // TODO: is this necessary?
                throwOp.loc = op.loc;
                stack.add(RuntimeException.newApexError(ctx, nativeThrown));
            }
            
        } while (!exitSuccess);

        // this vm is done:
        return stack[0];
        */
        
        System.assert(false, 'TODO');
        return null;
    }
    
    public static Object dispatchCall(Context ctx, Integer dispatchMode, Integer callFlags, Object funcVal, Object thisArg, Object[] argv) {
        /*
        // 11.2.3 [5.]
        if (!(funcVal instanceof Callable) || funcVal == null) {
            String valType = Utils.valueTypeToString(ctx, funcVal);
            throw new RuntimeException(ctx, new TypeError(ctx, valType + ' is not a function'));
        }
        
        VirtualMachine vm = ctx.vm;
        // 10.4.3
        if (funcVal instanceof MFunction) {
            MFunction mfunc = (MFunction) funcVal;
            // non-strict code tries to ensure that the thisArg is an object:
            if (!mfunc.code.strict)
                if (thisArg == null || thisArg == Utils.NUL)
                    thisArg = ctx.globalObj;
                else if (!(thisArg instanceof PlainObject))
                    thisArg = Utils.toObject(ctx, thisArg);
            
            if (dispatchMode == DISPATCH_SYNCHRONOUS) {
                // a native dispatch of an MFunction starts with a fork of the current Context and then instantiates a new vm on that fork; the MFunc
                // frame (a.k.a. ExecutionContext) is dispatched to the forked vm immediately before exec() is invoked on it:
                Context fork_ctx = ctx.clone();
                fork_ctx.parent = ctx;
                // this constructor will automatically setup "undefined" as the default return value for the new vm at its stack's bottom:
                VirtualMachine fork_vm = fork_ctx.vm = new VirtualMachine(fork_ctx);
                new Frame.MFunc(fork_ctx, mfunc, false, thisArg, argv);
                return fork_vm.exec();
            // else, dispatchMode == DISPATCH_ASYNC; asynchronous dispatch:
            } else {
                // if we meet all conditions for Tail Call Elimination (TCE), then hijack the active (caller) execution context rather than
                // instantiating a new one. the conditions are:
                // 1. this must be an async dispatch
                // 2. the CALL instruc must have been flagged as a TCE candidate, and the caller frame must be for an MFunction [[Call]]:
                if (callFlags != null && ((callFlags & Instruc.TCE_CANDIDATE_BIT) > 0) 
                        && vm.active.frameType == Frame.FT_MFUNCTION && !vm.active.isConstruct) {
                    Frame.MFunc callingFrame = (Frame.MFunc) vm.active;
                    // 3. the calling frame's MFunction must be the same instance as for this dispatch request;
                    // 4. the calling frame must not have an outstanding promise:
                    if (callingFrame.mfunc === mfunc && (vm.promises.size() == 0 || vm.promises[vm.promises.size() - 1].hostFrame !== callingFrame)) {
                        Frame.tailCallHijackSame(vm, callingFrame, mfunc, thisArg, argv);
                        return null;
                    }
                }
                // else, TCE conditions were not met...
                // setup undefined as the default return value into the calling frame's top stack slot (note that this step is not necessary when TCE
                // occurs above):
                vm.stack[vm.stack.size() - 1] = null;
                // instantiate a new exec context and push it onto the calls stack:
                new Frame.MFunc(ctx, mfunc, false, thisArg, argv);
                // asynchronous dispatch doesn't immediately return a value; the return value, when resolved, will be written into the top stack slot
                // in the calling frame:
                return null;
            }
        // for anything other than an MFunction, we'll invoke its internal [[Call]] method directly:
        } else {
            Integer callerIndex = vm.active.index;
            Integer callerReturnOffset = vm.stack.size() - 1;
            Callable thisCall = (Callable) funcVal;
            Frame.InternalCall internalCall = Frame.InternalCallProto.clone(); 
            internalCall.thisCall = thisCall;
            internalCall.dispatchOp = vm.op;
            vm.calls.add(internalCall);
            
            // invoke the internal [[Call]] method; this will either return an "immediate" result or throw a RuntimeException -- if the latter, then
            // the current state of the merged call stacks (with this call's Frame.InternalCall atop it, and including the call stacks of parent vm's
            // beneath this vm's calls) will be shallow-cloned and recorded in the exception. also note the special handling for direct calls to eval:
            Object returnVal;
            if (callFlags != null && (callFlags & Instruc.DIRECT_CALL_EVAL_BIT) > 0 && thisCall instanceof EvalFunction) {
                Frame callingFrame = vm.active;
                // a direct call to eval utilizes the lex/var environments, thisBinding, and strict-mode flag of the calling frame:
                returnVal = EvalFunction.evalImpl(ctx, callingFrame, argv);
            } else {
                // standard [[Call]], including indirect calls of eval (eval references the global env in this case):
                returnVal = thisCall.call(ctx, thisArg, argv);
            }
            
            // if we get here then [[Call]] returned without throwing an exception; remove the InternalCall frame from the calls stack:
            vm.calls.remove(callerIndex + 1);
            // clear the stack of all slots after the designated return value offset:
            for (Integer i=vm.stack.size() - 1; i > callerReturnOffset; i--)
                vm.stack.remove(i);
            
            // a few special Callable implementations (e.g. BoundFunction.[[Call]], Function.prototype.call, Function.prototype.apply) will return
            // the TailDispatchRequest singleton instance rather than an ECMAScript value or Reference -- in these cases the TailDispatchRequest
            // contains parameters for an immediate recursive dispatch of the same type. note that any such Callable method is responsible for
            // properly setting all necessary parameters on VirtualMachine.TailDispatchRequest. because Apex is single-threaded, we cannot have
            // conflicts over the singleton instance, so long as we use the result immediately.
            //
            // tail-dispatch allows the recursive dispatch to inherit its predecessor's dispatchMode & callFlags, and also allows for a clean removal
            // from vm.calls of the calling InternalCall/InternalConstruct, before dispatching the tail; this normalizes behavior between sync and
            // async modes, and ensures that the correct Frame.index value is set in async mode.
            // 
            // !! note that we don't support mixed dispatch types on a tail request -- i.e. no a tail [[Call]] on a [[Construct]], and no tail
            // [[Construct]] on a [[Call]]; I don't forsee any need for that functionality.
            if (returnVal == TailDispatchRequest) {
                // reuse the same dipatchMode and callFlags:
                returnVal = dispatchCall(ctx, dispatchMode, callFlags, 
                        TailDispatchRequest.funcVal, TailDispatchRequest.thisArg, TailDispatchRequest.argv);
                if (dispatchMode == DISPATCH_SYNCHRONOUS)
                    return returnVal;
                // there's nothing more to do in async mode for a tail dispatch; since we've already eliminated this dispatch's Frame.InternalCall
                // from the calls and values stacks, the tail-dispatched frame -- when exec'd -- will write its result into the correct original
                // caller's callerReturnOffset.
                else
                    return null;
            
            // else we got a normal return value on an async dispatch:
            } else if (dispatchMode == DISPATCH_ASYNC) {
                // perform the equivalent of an SID_RETURN instruction, writing the return value into the caller's top stack slot:
                vm.stack[callerReturnOffset] = returnVal;
                return null;
            // else we got a normal return value on an synchronous dispatch:
            } else
                return returnVal;
        }
        */
        
        System.assert(false, 'TODO');
        return null;
    }
    
    public static Object dispatchConstruct(Context ctx, Integer dispatchMode, Object funcVal, Object[] argv) {
        /*
        // 11.2.2 [4.]
        if (!(funcVal instanceof Constructible) || funcVal == null) {
            String valType;
            if (funcVal instanceof Function && funcVal != null)
                valType = Utils.toString(ctx, funcVal);
            else
                valType = Utils.valueTypeToString(ctx, funcVal);
                    
            throw new RuntimeException(ctx, new TypeError(ctx, valType + ' is not a constructor'));
        }
        
        VirtualMachine vm = ctx.vm;
        if (funcVal instanceof MFunction) {
            // !! note that MFunction constructor return values (placed in their calling frame's top stack slot) will undergo an additional check in
            // the vm's SID_RETURN processing -- if the value is not an object then the constructor's thisBinding is returned in its place:
            Mfunction mfunc = (MFunction) funcVal;
            // 13.2.2
            PlainObject thisArg = new PlainObject(ctx);
            // as an optimization, we first look for an own data property named "prototype", which should be available and correct in almost every
            // case, since "prototype" is not overridden in any custom getOwnProperty overrides (e.g. StringObject):
            PropertyDescrip protoDesc = mfunc.props.get('prototype');
            Object proto;
            if (protoDesc != null && protoDesc.isAccessor == false)
                proto = protoDesc.value;
            // if for some reason we didn't find an own "prototype" property, or it was an accessor, then invoke the more thorough and expensive
            // [[Get]] method:
            else
                proto = mfunc.get(ctx, 'prototype');
            
            if (proto != null && proto instanceof PlainObject) {
                thisArg.proto = (PlainObject) proto;
                // when customGetOwnProp is set to true, it must be inherited down the proto chain; this can only occur from built-in prototypes,
                // e.g. String.prototype:
                if (thisArg.proto.customGetOwnProp == true)
                    thisArg.customGetOwnProp = true;
            } else
                thisArg.proto = ctx.ObjectProto;
            
            if (dispatchMode == DISPATCH_SYNCHRONOUS) {
                // a native dispatch of an MFunction starts with a fork of the current Context and then instantiates a new vm on that fork; the MFunc
                // frame (a.k.a. ExecutionContext) is dispatched to the forked vm immediately before exec() is invoked on it:
                Context fork_ctx = ctx.clone();
                fork_ctx.parent = ctx;
                VirtualMachine fork_vm = fork_ctx.vm = new VirtualMachine(fork_ctx);
                // setup our calculated thisArg as the default return value for the new vm, by writing it into the stack bottom:
                fork_vm.stack[0] = thisArg;
                new Frame.MFunc(fork_ctx, mfunc, true, thisArg, argv);
                return fork_vm.exec();
            } else {
                // setup our calculated thisArg as the default return value into the calling frame's top stack slot:
                vm.stack[vm.stack.size() - 1] = thisArg;
                // asynchronous dispatch doesn't immediately return a value; the return value, when resolved, will be written into the top stack slot
                // in the caller frame:
                new Frame.MFunc(ctx, mfunc, true, thisArg, argv);
                return null;
            }
        // for anything other than an MFunction, we'll invoke its internal [[Construct]] method directly:
        } else {
            Integer callerIndex = vm.active.index;
            Integer callerReturnOffset = vm.stack.size() - 1;
            Constructible thisConstruct = (Constructible) funcVal;
            Frame.InternalConstruct internalConstruct = Frame.InternalConstructProto.clone(); 
            internalConstruct.thisConstruct = thisConstruct;
            internalConstruct.dispatchOp = vm.op;
            vm.calls.add(internalConstruct);
            // invoke the internal [[Construct]] method; this will either return an "immediate" result or throw a RuntimeException -- if the latter,
            // then the current state of the calls stack (including the this call's Frame.InternalConstruct atop it) will be shallow-cloned and
            // recorded in the exception:
            Object returnVal = thisConstruct.construct(ctx, argv);
            // if we get here then [[Construct]] returned without throwing out an exception; remove the InternalConstruct frame from the calls stack:
            vm.calls.remove(callerIndex + 1);
            // clear the stack of all slots after the designated return value offset:
            for (Integer i=vm.stack.size() - 1; i > callerReturnOffset; i--)
                vm.stack.remove(i);
            
            // a few special Constructible implementations (for now, only BoundFunction.[[Construct]]) will return the TailDispatchRequest singleton
            // instance rather than an ECMAScript value -- in these cases the TailDispatchRequest contains parameters for an immediate recursive
            // [[Construct]] dispatch. note that any [[Construct]] method which does this is responsible for properly setting all necessary
            // parameters on VirtualMachine.TailDispatchRequest.
            if (returnVal == TailDispatchRequest) {
                // reuse the same dispatchMode:
                returnVal = dispatchConstruct(ctx, dispatchMode, TailDispatchRequest.funcVal, TailDispatchRequest.argv);
                if (dispatchMode == DISPATCH_SYNCHRONOUS)
                    return returnVal;
                // there's nothing more to do in async mode for a tail dispatch; since we've already eliminated this dispatch's InternalConstruct
                // from the calls and values stacks, the tail-dispatched frame -- when exec'd -- will write its result into the correct original
                // caller's callerReturnOffset.
                else
                    return null;
            
            // else we got a normal return value on an async dispatch:
            } else if (dispatchMode == DISPATCH_ASYNC) {
                // perform the equivalent of an SID_RETURN instruction, writing the return value into the caller's top stack slot:
                vm.stack[callerReturnOffset] = returnVal;
                return null;
            // else we got a normal return value on a synchronous dispatch:
            } else
                return returnVal;
        }
        */
        
        System.assert(false, 'TODO');
        return null;
    }
    
    // Static Constructor:
    // instantiates a Virtual Machine instance that's setup to allow for repeated [[Call]] invocations of a given delegate function, where only the
    // thisArg and argv vary between invocations. each subsequent execution, via execDelegate, will synchronously return the delegate's result to the
    // host vm. this saves on the overhead of repeatedly forking off a new Context, instantiating a new Virtual Machine, and instantiating a new
    // frame. extremely useful for implementing native methods that delegate part of their functionality to lambda function arguments.
    //
    // example usage: efficient repeat execution of an Array.prototype.sort's compare function argument
    public static VirtualMachine newDelegator(Context hostCtx, Callable delegate) {
        /*
        Context delegatorCtx = hostCtx.clone();
        delegatorCtx.parent = hostCtx;
        VirtualMachine delegator = new VirtualMachine(delegatorCtx);

        // create the appropriate Frame for the given type of delegate function; this same Frame will be reused for each subsequent execDelegate:
        Frame delFrame;
        if (delegate instanceof MFunction) {
            // here we use the alternate Frame.MFunc constructor in order to bypass the initial Declaration Binding Instantiation:
            delFrame = delegator.mfuncDelegate = new Frame.MFunc(delegatorCtx, (Mfunction) delegate, false, null);
        } else {
            Frame.InternalCall internalCall = Frame.InternalCallProto.clone();
            internalCall.thisCall = delegate;
            internalCall.index = 0;
            internalCall.segStartIndex = 1;
            delFrame = delegator.callDelegate = internalCall;
            delegator.calls.add(internalCall);
        }
        // use the current op loc from the host vm (TODO: in future, consider making that a param):
        delFrame.dispatchOp = hostCtx.vm != null ? hostCtx.vm.op : null;
        return delegator;
        */
        
        System.assert(false, 'TODO');
        return null;
    }
    
    // each call to execDelegate will reset the desired start state on the delegator vm's calls stack and values stack; the delegate frame is also
    // reset to point at the 0th instruc and updated for the new thisArg and argv (i.e. recalc Declaration Binding Instantiation):
    public static Object execDelegate(VirtualMachine vm, Object thisArg, Object[] argv) {
        /*
        Context ctx = vm.ctx;
        
        // reset the calls stack to the start state, with only the delegate frame on it -- note that the delegate's (index==0) frame will not be
        // removed by the vm's execution, so if we have only 1 frame on the stack then that's it:
        if (vm.calls.size() != 1) {
            vm.calls.clear();
            if (vm.mfuncDelegate != null)
                vm.calls.add(vm.mfuncDelegate);
            else
                vm.calls.add(vm.callDelegate);
        }
        // reset the values stack to the start state:
        if (vm.stack.size() != 1) {
            vm.stack.clear();
            vm.stack.add(null);
        } else
            vm.stack[0] = null;
            
        // !! note that promises will never linger from a prior execution (self-clearing, as all abrupt completions must go through them), so we need
        // not clear them manually (TODO: verify that this is absolutely correct)...
        
        if (vm.mfuncDelegate != null) {
            MFunction mfunc = vm.mfuncDelegate.mfunc;
            // non-strict code tries to ensure that the thisArg is an object:
            if (!vm.mfuncDelegate.strict)
                if (thisArg == null || thisArg == Utils.NUL)
                    thisArg = ctx.globalObj;
                else if (!(thisArg instanceof PlainObject))
                    thisArg = Utils.toObject(ctx, thisArg);
            
            Frame.prepareDelegate(vm, vm.mfuncDelegate, thisArg, argv);
            return vm.exec();
        // else we must have a callDelegate for an internal [[Call]] -- if not we'll hit a NullPointerException (but this should never happen so long
        // as my code is infallible):
        } else {
            // a native function delegate won't be able to push onto the values stack unless it returns a tail dispatch request for an MFunction,
            // which can in turn be dispatched asynchronously into this vm. the logic below accounts for this (stack will already have been reset as
            // necessary):
            
            Frame.InternalCall delFrame = vm.callDelegate;
            // note there are no attributes on vm.callDelegate that require updating for a subsequent exec:
            Object returnVal = delFrame.thisCall.call(ctx, thisArg, argv);
            // if the delegate returned a tail-dispatch request, then we need some special logic to dispatch it:
            if (returnVal == TailDispatchRequest) {
                // prepare the root InternalCallFrame to curry a return value from the tail-dispatch; this must be done asynchronously:
                delFrame.next = 0;
                // asynchronous dispatch; the root InternalCallFrame -- prepared above -- will receive the return value in its stack and then curry
                // it to vm.returnVal via its [RESULT, END] instrucs segment:
                dispatchCall(ctx, DISPATCH_ASYNC, null, TailDispatchRequest.funcVal, TailDispatchRequest.thisArg, TailDispatchRequest.argv);
                // we dispatched asynchronously to a vm that hadn't start its processing loop; this exec() will fire off and complete everything: 
                return vm.exec();
            // else the delegate returned a normal value:
            } else
                return returnVal;
        }
        */
        
        System.assert(false, 'TODO');
        return null;
    }
    
    public class TailDispatch {
        public Object funcVal;
        public Object thisArg; // this parameter is not used by [[Construct]] dispatch requests
        public Object[] argv;
        // TODO: add a "what" parameter that specifies function/eval/global
        
        private TailDispatch() { }
    }
    
    // the singleton instance:
    public static final TailDispatch TailDispatchRequest = new TailDispatch();
}