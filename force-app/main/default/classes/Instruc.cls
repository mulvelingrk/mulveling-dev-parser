/*
 * Mike Ulveling
 */
public virtual class Instruc {
    static Integer next_id = 0;
    static Integer iid() {
        return next_id++;
    }
    
    public static final Integer OP_GOTO = iid();
    public static final Integer OP_BRCHF = iid();
    public static final Integer OP_BRCHT = iid();
    public static final Integer OP_JMPF = iid();
    public static final Integer OP_JMPT = iid();
    public static final Integer OP_JMP = iid();
    public static final Integer OP_SWCHCMP = iid();
    
    public static final Integer OP_PUSH = iid();
    public static final Integer OP_POP = iid();
    public static final Integer OP_POPPEN = iid();
    public static final Integer OP_SWP = iid();
    public static final Integer OP_CPY = iid();
    public static final Integer OP_CPYPEN = iid();
    public static final Integer OP_FORK = iid();
    public static final Integer OP_CPYVAL = iid();
    public static final Integer OP_PREPEN = iid(); // TODO: this may not be needed
    
    public static final Integer OP_ENVREF = iid();
    public static final Integer OP_PROPREF = iid();
    public static final Integer OP_STKREF = iid();
    public static final Integer OP_ENVVAL = iid();
    public static final Integer OP_PROPVAL = iid();
    public static final Integer OP_STKVAL = iid();
    
    public static final Integer OP_THIS = iid();
    public static final Integer OP_FUNCEXP = iid();
    public static final Integer OP_REGEXP = iid();
    
    public static final Integer OP_PUT = iid();
    public static final Integer OP_IMMUT = iid(); // mutation of OP_PUT when its target is a stack allocation for an immutable binding
    
    public static final Integer OP_PRIM = iid();
    public static final Integer OP_BOOL = iid();
    public static final Integer OP_NUM = iid();
    public static final Integer OP_INT32 = iid();
    public static final Integer OP_UINT32 = iid();
    public static final Integer OP_STR = iid();
    
    public static final Integer OP_BTOR = iid();
    public static final Integer OP_BTXOR = iid();
    public static final Integer OP_BTAND = iid();
    
    public static final Integer OP_EQ = iid();
    public static final Integer OP_NEQ = iid();
    public static final Integer OP_STEQ = iid();
    public static final Integer OP_STNEQ = iid();
    
    public static final Integer OP_IN = iid();
    public static final Integer OP_INSTOF = iid();
    public static final Integer OP_JMP2STR = iid();
    public static final Integer OP_GT = iid();
    public static final Integer OP_GTEQ = iid();
    public static final Integer OP_LT = iid();
    public static final Integer OP_LTEQ = iid();
    
    public static final Integer OP_LSHFT = iid();
    public static final Integer OP_RSHFT = iid();
    public static final Integer OP_URSHFT = iid();
    
    public static final Integer OP_MULT = iid();
    public static final Integer OP_DIV = iid();
    public static final Integer OP_MOD = iid();
    
    public static final Integer OP_ADD = iid();
    public static final Integer OP_ADDNUM = iid();
    public static final Integer OP_SUB = iid();
    
    public static final Integer OP_OBJLIT = iid();
    public static final Integer OP_OBJPROP = iid();
    public static final Integer OP_OBJGET = iid();
    public static final Integer OP_OBJSET = iid();
    
    public static final Integer OP_ARRLIT = iid();
    public static final Integer OP_ARRADD = iid();
    public static final Integer OP_ARREND = iid();
    
    public static final Integer OP_ARGV = iid();
    public static final Integer OP_ARGVADD = iid();
    public static final Integer OP_CALL = iid();
    public static final Integer OP_NEW = iid();
    
    public static final Integer OP_INC = iid();
    public static final Integer OP_DEL = iid();
    public static final Integer OP_LOGNOT = iid();
    public static final Integer OP_BITNOT = iid();
    public static final Integer OP_NEG = iid();
    public static final Integer OP_JMPREFOK = iid();
    public static final Integer OP_TYPEOF = iid();
    
    public static final Integer OP_RESULT = iid();
    public static final Integer OP_RETRES = iid();
    public static final Integer OP_RETNONE = iid();
    public static final Integer OP_RETTOP = iid();
    public static final Integer OP_RETDEF = iid();
    public static final Integer OP_RETEXP = iid();
    
    public static final Integer OP_BRK = iid();
    public static final Integer OP_CONT = iid();
    public static final Integer OP_STOLEX = iid();
    public static final Integer OP_RESTBLOK = iid();
    public static final Integer OP_JSR = iid();
    public static final Integer OP_RSR = iid();
    public static final Integer OP_CATCH = iid();
    public static final Integer OP_THROW = iid();
    
    public static final Integer OP_ENUM = iid();
    public static final Integer OP_ENUMNXT = iid();
    public static final Integer OP_WITH = iid();
    
    public Integer opCode;
    public String strVal;
    public Boolean boolVal; // used for flags (up to 3 states)
    public Integer intVal; // typically used to store an instruction jump address or an offset
    public Object objVal;
    
    public Lexer2.Token loc;
    // the instruc address to route to (either the start of a explicit catch block or an implicit catch) if a yet-unhandled error is thrown while
    // this instruc is dispatched:
    public Integer errAddr;
    
    Instruc() {}
    
    public class Swap extends Instruc {
        public Swap() {
            this.opCode = OP_SWP;
        }
        
        public override String toString() { return 'SWP'; }
    }
    
    // assumes the value atop the stack is a reference value. copies this reference (stack size + 1), and then dereferences the new top. this op is
    // equivalent to a [CPY VAL] sequence
    public class CopyDerefVal extends Instruc {
        public CopyDerefVal(Lexer2.Token loc) {
            this.opCode = OP_CPYVAL;
            this.loc = loc;
        }
        
        public override String toString() { return 'CPYVAL'; }
    }
    
    // inserts a copy of the top stack slot before the penultimate slot. increases stack size by 1, while the values in the top and penultimate slots
    // remain the same as before. 
    //
    // Impl:
    // stack.add(top - 2, stack[top]);
    public class ForkTop extends Instruc {
        public ForkTop() {
            this.opCode = OP_FORK;
        }
        
        public override String toString() { return 'FORK'; }
    }
    
    // some unary operations may flag their operand as the penultimate slot rather than the top slot (the latter being default):
    public static final Boolean TOP_OP = false;
    public static final Boolean PEN_OP = true;

    // some of the type preprocessing instructions may use 2 passes (e.g. ToNum, ToInt32):
    public static final Integer ONE_PASS = null;
    public static final Integer PASS_A = 1;
    public static final Integer PASS_B = 2;
    
    // hint flags for the ToPrim instruc:
    public static final Integer NO_HINT = 0;
    public static final Integer STR_HINT = 1;
    public static final Integer NUM_HINT = 2;
    
    // assert:
    //    1 operand atop the stack; it must be an object value
    // attrs:
    // intVal:
    //    null => no hint; toString/valueOf precedence is determined at runtime by the operand type (string for Date values; number for all other values)
    //    0    => string hint; toString has precedence over valueOf
    //    1    => number hint; valueOf has precedence over toString
    public class ToPrim extends Instruc {
        public ToPrim(Lexer2.Token loc, Integer hintFlag, Boolean penOperand) {
            this.opCode = OP_PRIM;
            this.loc = loc;
            this.intVal = hintFlag;
            this.boolVal = penOperand;
        }
        
        public override String toString() { return 'PRIM' 
                + (intVal == STR_HINT ? '[STR]' : (intVal == NUM_HINT ? '[NUM]' : '')) + (boolVal == true ? '[PEN]' : ''); }
    }
    
    public class ToBool extends Instruc {
        public ToBool(Lexer2.Token loc, Integer passNum, Boolean penOperand) {
            this.opCode = OP_BOOL;
            this.loc = loc;
            this.intVal = passNum;
            this.boolVal = penOperand;
        }
        
        public override String toString() { return 'BOOL' + (intVal == 1 ? '[A]' : (intVal == 2 ? '[B]' : '')) + (boolVal == true ? '[PEN]' : ''); }
    }
    
    public class ToNum extends Instruc {
        public ToNum(Lexer2.Token loc, Integer passNum, Boolean penOperand) {
            this.opCode = OP_NUM;
            this.loc = loc;
            this.intVal = passNum;
            this.boolVal = penOperand;
        }
        
        public override String toString() { return 'NUM' + (intVal == 1 ? '[A]' : (intVal == 2 ? '[B]' : '')) + (boolVal == true ? '[PEN]' : ''); }
    }
    
    public class ToInt32 extends Instruc {
        public ToInt32(Lexer2.Token loc, Integer passNum, Boolean penOperand) {
            this.opCode = OP_INT32;
            this.loc = loc;
            this.intVal = passNum;
            this.boolVal = penOperand;
        }
        
        public override String toString() { return 'INT32' + (intVal == 1 ? '[A]' : (intVal == 2 ? '[B]' : '')) + (boolVal == true ? '[PEN]' : ''); }
    }
    
    public class ToUint32 extends Instruc {
        public ToUint32(Lexer2.Token loc, Integer passNum, Boolean penOperand) {
            this.opCode = OP_UINT32;
            this.loc = loc;
            this.intVal = passNum;
            this.boolVal = penOperand;
        }
        
        public override String toString() { return 'UINT32' + (intVal == 1 ? '[A]' : (intVal == 2 ? '[B]' : '')) + (boolVal == true ? '[PEN]' : ''); }
    }
    
    public class ToStr extends Instruc {
        public ToStr(Lexer2.Token loc, Integer passNum, Boolean penOperand) {
            this.opCode = OP_STR;
            this.loc = loc;
            this.intVal = passNum;
            this.boolVal = penOperand;
        }
        
        public override String toString() { return 'STR' + (intVal == 1 ? '[A]' : (intVal == 2 ? '[B]' : '')) + (boolVal == true ? '[PEN]' : ''); }
    }
    
    // boolVal flag values for the LessThan/GreaterThan/LessThanEquals/GreaterThanEquals relational comparison ops:
    public static final Boolean LEXICAL_RELCMP = true;
    public static final Boolean NUMERIC_RELCMP = false;
    
    // TODO: define the attribs and impl for the following 4 relational comparison ops:
    
    public class LessThan extends Instruc {
        public LessThan(Boolean relCmpType, Integer addrInc) {
            this.opCode = OP_LT;
            this.boolVal = relCmpType;
            this.intVal = addrInc;
        }
        
        public override String toString() { return 'LT' + (boolVal == LEXICAL_RELCMP ? '[LEX]' + (intVal != null ? '[' + intVal + ']' : '') : ''); }
    }
    
    public class GreaterThan extends Instruc {
        public GreaterThan(Boolean relCmpType, Integer addrInc) {
            this.opCode = OP_GT;
            this.boolVal = relCmpType;
            this.intVal = addrInc;
        }
        
        public override String toString() { return 'GT' + (boolVal == LEXICAL_RELCMP ? '[LEX]' + (intVal != null ? '[' + intVal + ']' : '') : ''); }
    }
    
    public class LessThanEquals extends Instruc {
        public LessThanEquals(Boolean relCmpType, Integer addrInc) {
            this.opCode = OP_LTEQ;
            this.boolVal = relCmpType;
            this.intVal = addrInc;
        }
        
        public override String toString() { return 'LTEQ' + (boolVal == LEXICAL_RELCMP ? '[LEX]' + (intVal != null ? '[' + intVal + ']' : '') : ''); }
    }
    
    public class GreaterThanEquals extends Instruc {
        public GreaterThanEquals(Boolean relCmpType, Integer addrInc) {
            this.opCode = OP_GTEQ;
            this.boolVal = relCmpType;
            this.intVal = addrInc;
        }
        
        public override String toString() { return 'GTEQ' + (boolVal == LEXICAL_RELCMP ? '[LEX]' + (intVal != null ? '[' + intVal + ']' : '') : ''); }
    }
    
    // this flag only applies to ENVVAL and STKVAL opcodes
    public static final Boolean FLG_PUSH_THIS = true;
    
    // !! this intruc's opCode may be mutated to OP_STKREF during pass2 compilation of the host code unit; once mutated in this fashion, the intVal
    // attribute will also be redefined and overwritten (see below).
    //
    // opCode may be mutated to OP_ENVVAL during pass1 compilation, and may later be mutated to STKREF or STKVAL in pass2.
    //
    // attributes:
    // intVal
    //    pass1: set to the Lexer2.ttype of the token that was parsed for the environment reference's name
    //    pass2: if opCode is mutated to STKREF, then this attr will subsequently be overwritten with the resolved segOffset of its stack slot
    // boolVal
    //    setting to FLG_PUSH_THIS in combination with a mutated opcode of ENVVAL or STKVAL will push the matched env's provided this value before
    //    the resolved value (i.e. 2 values are pushed to the stack in that case, instead of the usual 1 for this operation). note that STKREF will
    //    always push undefined for the this value, as this is specified for all declarative envs. 
    // putOp
    //     Records the assignment op corresponding to this ENVREF; this must be an Instruc with an opcode of PUT. If this ENVREF is converted to a
    //     stack allocation (in pass2) of an immutable binding, then pass2 will record this ENVREF's variable name into putOp.strVal and will
    //     mutate its opCode to IMMUT. This facilitates a proper error message in strict mode, and a relatively efficient no-op in non-strict mode.
    public class EnvRef extends Instruc {
        // must be a PUT:
        public Instruc.Put putOp;
        
        public EnvRef(String identName) {
            this.opCode = OP_ENVREF;
            this.strVal = identName;
        }
        
        public virtual override String toString() {
            return (opCode == OP_STKVAL ? 'STKVAL' : (opCode == OP_STKREF ? 'STKREF' : (opCode == OP_ENVVAL ? 'ENVVAL' : 'ENVREF'))) 
                    // the FLG_PUSH_THIS should only apply to ENVVAL and STKVAL:
                    + (boolVal == FLG_PUSH_THIS ? '[THIS]' : '') + '[' + strVal + ']';
        }
    }
    
    // flags a PROPREF as dynamic (vs. static):
    public static final Boolean FLG_DYNA_PROP = true;
    
    // opCode may be mutated to OP_PROPVAL during pass1 compilation
    //
    // attributes:
    // strVal
    //    the static property name; may not be used in conjunction with boolVal=FLG_DYNA_PROP
    // boolVal
    //    setting to FLG_DYNA_PROP flags this as a dynamic property 
    public class PropRef extends Instruc {
        // constructor for static property refs:
        public PropRef(Lexer2.Token loc, String staticPropName) {
            this.opCode = OP_PROPREF;
            this.loc = loc;
            this.strVal = staticPropName;
        }
        
        // constructor for dynamic property refs:
        public PropRef(Lexer2.Token loc) {
            this.loc = loc;
            this.boolVal = FLG_DYNA_PROP;
        }
        
        public override String toString() { return (opCode == OP_PROPVAL ? 'PROPVAL' : 'PROPREF') + (boolVal == FLG_DYNA_PROP ? '[D]' : ''); }
    }
    
    // pushes a simple primitive literal value atop the stack
    public class Push extends Instruc {
        public Push(Object val) {
            this.opCode = OP_PUSH;
            this.objVal = val;
        }
        
        public virtual override String toString() {
            String strVal;
            if (objVal == null) {
                strVal = 'undefined';
            } else if (objVal instanceof String) {
                strVal = '"' + objVal + '"';
            } else if (objVal instanceof Boolean || objVal instanceof Double) {
                strVal = String.valueOf(objVal);
            } else if (objVal == Elision.Instance)  {
                strVal = '<elision>';
            } else if (objVal == Utils.NUL) {
                strVal = 'null';
            } else {
                strVal = '<object>';
            }
            return 'PUSH[' + strVal + ']';
        }
    }
    
    // Removes the stack top and inserts it before the new pen (formerly pre-pen) slot. Used by native String.prototype methods for preprocessing --
    // via [STR[A] STR[B] PREPEN CALL], after pushing [<funcVal>, <argv>, <thisArg>] atop the stack -- when the thisArg value is not a string.
    //
    // Impl:
    // Integer top = stack.size() - 1;
    // stack.add(top - 2, stack.remove(top));
    public class PrePen extends Instruc {
        public PrePen() {
            this.opCode = OP_PREPEN;
        }
        
        public virtual override String toString() {
            return 'PREPEN';
        }
    }
    
    public class ThisRef extends Instruc {
        public ThisRef() {
            this.opCode = OP_THIS;
        }
        
        public virtual override String toString() {
            return 'THIS';
        }
    }
    
    public class RegexpLit extends Instruc {
        public RegexpLit(String spatt, String flags) {
            this.opCode = OP_REGEXP;
            // 'g' is a valid ECMAScript RegExp flag but not a valid Java Pattern flag, so don't feed it in to the Apex Pattern:
            String flagsSansGlobal = flags.replaceAll('g', '');
            this.objVal = Pattern.compile(flagsSansGlobal.length() > 0 ? '(?' + flagsSansGlobal + ')' + spatt : spatt);
            this.strVal = flags;
        }
        
        public virtual override String toString() {
            return 'REGEXP[' + ((Pattern) objVal).pattern() + '][' + strVal + ']';
        }
    }
    
    // impl:
    // stack.push(new MFunction(ctx, active.lexEnv, (CodeContext.Function) this.objVal))
    public class FuncExpr extends Instruc {
        public FuncExpr(CodeContext.Function funcCode) {
            this.opCode = OP_FUNCEXP;
            this.objVal = funcCode;
        }
        
        public virtual override String toString() {
            return 'FUNCEXP[' + ((CodeContext.Function) objVal).getTraceName(null) + ']';
        }
    }
    
    // Statement-level unconditional branch.
    //
    // active.addr = op.intVal
    // continue
    public class GoToAddr extends Instruc {
        public GoToAddr() {
            this.opCode = OP_GOTO;
        }
        
        public override String toString() { return 'GOTO[' + intVal + ']'; }
    }
    
    // Statement-level branch. Unconditionally removes top of stack.
    //
    // topVal = stack.remove(top)
    // if (topVal == false)
    //     active.addr = op.intVal
    // else
    //     active.addr++
    // continue
    public class BranchOnFalse extends Instruc {
        public BranchOnFalse() {
            this.opCode = OP_BRCHF;
        }
        
        public override String toString() { return 'BRCHF[' + intVal + ']'; }
    }
    
    // Statement-level branch. Unconditionally removes top of stack.
    //
    // topVal = stack.remove(top)
    // if (topVal == true)
    //     active.addr = op.intVal
    // else
    //     active.addr++
    // continue
    public class BranchOnTrue extends Instruc {
        public BranchOnTrue() {
            this.opCode = OP_BRCHT;
        }
        
        public override String toString() { return 'BRCHT[' + intVal + ']'; }
    }
    
    // Expression-level branch. Unconditionally removes top of stack. Jumps differ from Branches in that they add an increment to the current addr
    // rather than directly setting a precalculated addr offset.
    //
    // topVal = stack.remove(top)
    // if (topVal == false)
    //     active.addr += op.intVal
    // else
    //     active.addr++
    // continue
    public class JumpOnFalse extends Instruc {
        public JumpOnFalse() {
            this.opCode = OP_JMPF;
        }
        
        public JumpOnFalse(Integer jumpSize) {
            this.opCode = OP_JMPF;
            this.intVal = jumpSize;
        }
        
        public override String toString() { return 'JMPF[' + intVal + ']'; }
    }
    
    // Expression-level branch. Unconditionally removes top of stack. Jumps differ from Branches in that they add an increment to the current addr
    // rather than directly setting a precalculated addr offset.
    //
    // topVal = stack.remove(top)
    // if (topVal == true)
    //     active.addr += op.intVal
    // else
    //     active.addr++
    // continue
    public class JumpOnTrue extends Instruc {
        public JumpOnTrue() {
            this.opCode = OP_JMPT;
        }
        
        public JumpOnTrue(Integer jumpSize) {
            this.opCode = OP_JMPT;
            this.intVal = jumpSize;
        }
        
        public override String toString() { return 'JMPT[' + intVal + ']'; }
    }
    
    // Expression-level branch. Unconditional; does not modify stack. Jumps differ from Branches in that they add an increment to the current addr
    // rather than directly setting a precalculated addr offset.
    //
    // active.addr += op.intVal
    // continue
    public class Jump extends Instruc {
        public Jump() {
            this.opCode = OP_JMP;
        }
        
        public Jump(Integer jumpSize) {
            this.opCode = OP_JMP;
            this.intVal = jumpSize;
        }
        
        public override String toString() { return 'JMP[' + intVal + ']'; }
    }
    
    // Expression-level branch. Used exclusively by the relational comparison op sequence; routes to either the lexical or numeric version of the
    // relational cmp op. Does not modify the stack. Jumps differ from Branches in that they add an increment to the current addr rather than
    // directly setting a precalculated addr offset.
    //
    // rhs = stack[top]
    // lhs = stack[top - 1]
    // if (lhs instanceof String && rhs instanceof String && lhs != null && rhs != null)
    //     active.addr ++
    // else
    //     active.addr += 2
    // continue
    public class JumpOnTwoStrings extends Instruc {
        // default jump is 2, as currently that is the only usage of this instruc:
        public JumpOnTwoStrings() {
            this.opCode = OP_JMP2STR;
            this.intVal = 2;
        }
        
        public JumpOnTwoStrings(Integer jumpSize) {
            this.opCode = OP_JMP2STR;
            this.intVal = jumpSize;
        }
        
        public override String toString() { return 'JMP2STR[' + intVal + ']'; }
    }
    
    // Expression-level branch. Used by the typeof op sequence. A reference value must be atop the stack. Increments addr by intVal if this ref is
    // resolvable. 
    //
    // Impl:
    // Object r = stack[top];
    // if (r instanceof Integer)
    //     active.addr++
    // else 
    //     Reference ref = (Reference) r;
    //     if (ref.objBase != null || ref.decEnvBase != null || ref.objEnvBase != null)
    //         active.addr++
    //     else
    //         active.addr += op.intVal
    // continue
    public class JumpIfRefResolved extends Instruc {
        public JumpIfRefResolved() {
            this.opCode = OP_JMPREFOK;
        }
        
        public JumpIfRefResolved(Integer jumpSize) {
            this.opCode = OP_JMPREFOK;
            this.intVal = jumpSize;
        }
        
        public override String toString() { return 'JMPREFOK[' + intVal + ']'; }
    }
    
    // Statement-level branch. Used exclusively by the switch statement.
    //
    // impl:
    // bval = Utils.strictEquality(stack.remove(top), stack[top - 1]); top and pen are non-ref values. remove the top <caseExpr_i> value.
    // if bval == true
    //     stack.remove(top - 1) ; pop the <switchExpr> value
    //     active.addr = op.intVal ; jump to the relevant <caseStmts_i>.addr
    //     continue
    // else
    //     addr ++
    //     continue
    //
    // attributes:
    // intVal must be resolved to a jump offset
    public class SwitchCmp extends Instruc {
        public SwitchCmp() {
            this.opCode = OP_SWCHCMP;
        }
        
        public virtual override String toString() {
            return 'SWCHCMP[' + intVal + ']';
        }
    }

    // Stack top is a non-ref value. Pops this value and writes it into the frame's designated result slot (always the 1st slot for a global code or
    // eval code frame).
    // 
    // Impl:
    // stack[active.segStartIndex] = stack.remove(top)
    // * fallthrough to standard addr++ continue
    public class Result extends Instruc {
        public Result() {
            this.opCode = OP_RESULT;
        }
        
        public virtual override String toString() {
            return 'RESULT';
        }
    }
    
    // RETRES can only exist in global code and eval code frames, which are guaranteed to allocate a result stack slot (1st slot).
    // 
    // Impl:
    // while (top > active.segStartIndex)
    //     stack.remove(top--)
    // * top now points to the result slot (i.e. the 1st slot in the returning frame), and top-1 points to the active slot from the calling frame:
    // stack[top - 1] = stack.remove(top);
    // * note that top is no longer accurate (too large by 1)
    // calls.remove(active.index)
    // if (active.index == 0)
    //     exitSuccess = true
    //     break
    //     * the vm's exec() method will halt its processing loop and return the result at stack[0]
    // else
    //     active = calls[active.index - 1]
    //     * fallthrough to standard active.addr++ continue
    // TODO: consider pooling frames
    public class ReturnResult extends Instruc {
        public ReturnResult() {
            this.opCode = OP_RETRES;
        }
        
        public virtual override String toString() {
            return 'RETRES';
        }
    }
    
    // RETNONE is used e.g. by native methods that result in a tail dispatch. Only exists in native functions.
    // 
    // Impl:
    // while (top >= active.segStartIndex)
    //     stack.remove(top--)
    // * top now points to the active slot from the calling frame:
    // calls.remove(active.index)
    // active = calls[active.index - 1]
    // * fallthrough to standard active.addr++ continue
    // TODO: consider pooling frames
    public class ReturnNone extends Instruc {
        public ReturnNone() {
            this.opCode = OP_RETNONE;
        }
        
        public virtual override String toString() {
            return 'RETNONE';
        }
    }
    
    // RETTOP returns the top of the stack without additional checking. Only exists in native functions.
    // 
    // Impl:
    // stack[active.segStartIndex - 1] = stack.remove(top--)
    // while (top >= active.segStartIndex)
    //     stack.remove(top--)
    // * now top points to the active slot from the calling frame:
    // calls.remove(active.index)
    // active = calls[active.index - 1]
    // * fallthrough to standard active.addr++ continue
    // TODO: consider pooling frames
    public class ReturnTop extends Instruc {
        public ReturnTop() {
            this.opCode = OP_RETTOP;
        }
        
        public virtual override String toString() {
            return 'RETTOP';
        }
    }
    
    // RETDEF returns the default value for the current function frame, i.e. undefined for a call invocation, and the thisBinding for a constructor.
    // Only exists in function code.
    // 
    // Impl:
    // if (active.isConstruct)
    //     stack[active.segStartIndex - 1] = active.thisBinding
    // else
    //     stack[active.segStartIndex - 1] = null
    // while (top >= active.segStartIndex)
    //     stack.remove(top--)
    // * top now points to the active slot from the calling frame:
    // calls.remove(active.index)
    // active = calls[active.index - 1]
    // * fallthrough to standard active.addr++ continue
    // TODO: consider pooling frames
    public class ReturnDefault extends Instruc {
        public ReturnDefault() {
            this.opCode = OP_RETDEF;
        }
        
        public virtual override String toString() {
            return 'RETDEF';
        }
    }
    
    // RETEXP returns the top of the stack, but with an additional condition/branch when returning from constructor code.
    // 
    // Impl:
    // if (active.isConstruct && (stack[top] == null || !(stack[top] instanceof PlainObject)))
    //     stack[active.segStartIndex - 1] = active.thisBinding
    // else
    //     stack[active.segStartIndex - 1] = stack.remove(top--)
    // while (top >= active.segStartIndex)
    //     stack.remove(top--)
    // * top now points to the active slot from the calling frame:
    // calls.remove(active.index)
    // active = calls[active.index - 1]
    // * fallthrough to standard active.addr++ continue
    // TODO: consider pooling frames
    public class ReturnExpr extends Instruc {
        public ReturnExpr() {
            this.opCode = OP_RETEXP;
        }
        
        public virtual override String toString() {
            return 'RETEXP';
        }
    }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    /* 
     * Instruc Layouts for TryStatements:
     */
     
    /* 
     * I. try-catch:
     * 
     * STOLEX ; required start of each try block
     * <parsed try instrucs>
     * ; try block terminating instrucs:
     * JSR[boolVal=false][intVal=null][returnAddr=GOTO] ; no value curry, and no jump addr (because there's no finally block)
     * GOTO[<end>]
     * 
     * CATCH ; explicit catch block instantiation
     * <parsed catch instrucs>
     * ; catch block terminating instrucs:
     * JSR[boolVal=false][intVal=null][returnAddr=GOTO] ; no value curry, and no jump addr (because there's no finally block)
     * GOTO[<end>]
     * 
     * ; implicit catch instrucs (required for all layouts of TryStatement):
     * JSR_IC[boolVal=true][intVal=null][returnAddr=THROW] ; JSR flagged as implicit-catch. curry the thrown value atop the stack (i.e. to the
     *                                                     ; subsequent THROW), no jump addr
     * THROW
     *
     * <end>
     * 
     * after serialization:
     *   1. all members of <parsed try instrucs>, that do not already have a non-null errAddr (i.e. from a nested try or catch), should set errAddr
     *      to the explicit catch block's start addr (i.e. the CATCH instruc)
     *   2. all members of <parsed catch instrucs>, that do not already have a non-null errAddr (i.e. from a nested try or catch), should set errAddr
     *      to the implicit catch's first instruc
     * 
     */
    
    /* II. try-finally:
     * 
     * STOLEX ; start of try block
     * <parsed try instrucs>
     * ; try block terminating instrucs:
     * JSR[boolVal=false][intVal=<start of finally block>][returnAddr=GOTO] ; no value curry, but jump addr is set
     * GOTO[<end>]
     * 
     * ; implicit catch instrucs (output for all layouts):
     * JSR_IC[boolVal=true][intVal=<start of finally block>][returnAddr=THROW] ; JSR flagged as implicit-catch. curry the thrown val, jump addr set
     * THROW
     * 
     * ; explicit finally block -- note that no special instruc need delimit the start of a finally block, because it can only be entered via JSR,
     * ; which will perform all necessary block restorations
     * <parsed finally instrucs>
     * RSR ; finally block terminating instruc -- this will restore to the appropriate block state for the next instruc after the TryStatement
     *
     * <end>
     * 
     * after serialization:
     *   1. all members of <parsed try instrucs>, that do not already have a non-null errAddr (i.e. from a nested try or catch), should set errAddr
     *      to the implicit catch's first instruc
     *
     */
    
    /* III. try-catch-finally:
     * 
     * STOLEX ; start of try block
     * <parsed try instrucs>
     * ; try block terminating instrucs:
     * JSR[boolVal=false][intVal=<start of finally block>][returnAddr=GOTO] ; no value curry, but jump addr is set
     * GOTO[<end>]
     * 
     * CATCH ; explicit catch block
     * <parsed catch instrucs>
     * ; catch block terminating instrucs:
     * JSR[boolVal=false][intVal=<start of finally block>][returnAddr=GOTO] ; no value curry, but jump addr is set
     * GOTO[<end>]
     * 
     * ; implicit catch instrucs (output for all layouts):
     * JSR_IC[boolVal=true][intVal=<start of finally block>][returnAddr=THROW] ; JSR flagged as implicit-catch. curry the thrown value, jump addr set
     * THROW
     * 
     * ; explicit finally block -- note that no special instruc need delimit the start of a finally block, because it can only be entered via JSR
     * <parsed finally instrucs>
     * RSR ; finally block terminating instruc -- this will restore to the appropriate block state for the next instruc after the TryStatement
     *
     * <end>
     * 
     * after serialization:
     *   1. all members of <parsed try instrucs>, that do not already have a non-null errAddr (i.e. from a nested try or catch), should set errAddr
     *      to the explicit catch block's start addr
     *   2. all members of <parsed catch instrucs>, that do not already have a non-null errAddr (i.e. from a nested try or catch), should set errAddr
     *      to the implicit catch's first instruc
     */
    
    // Store Lexical-Environment Record
    // Takes the lexEnv of the active code unit and pushes it onto the stack. Always serialized as the 1st instruc in a try block.
    //
    // attributes: none
    //
    // implementation:
    // stack.add(active.lexEnv)
    public class StoreLex extends Instruc {
        public StoreLex() {
            this.opCode = OP_STOLEX;
        }
        
        public virtual override String toString() {
            return 'STOLEX';
        }
    }
    
    // implementation for <Standard Block Restore>:
    // if lexEnvRestore != null
    //     active.lexEnv = stack[lexEnvRestore]
    // if stackRestore != null
    //     while top >= stackRestore
    //         stack.remove(top--);
    public abstract class BlockControl extends Instruc {
        // these Block-AST variables are set during pass1 compilation, and are necessary to resolve offsets/addresses in pass2:
        public BlockContext startBlock; // required only for block-control instrucs that may do a multi-bock jump
        public BlockContext targetBlock; // required for all block-control instrucs
        
        // segmented stack offsets to be resolved in pass2 with the aid of the Block AST:
        public Integer lexEnvRestore;
        public Integer stackRestore;
        
        public abstract void resolvePass2();
    }
    
    // resolves the stackLexEnv and stackRestore offsets for instrucs that potentially jump through multiple nested blocks from startBlock to
    // targetBlock; restores to the point immediately before instantiation of the targetBlock. a different calculation is necessary for these cases
    // because the lexEnvRestore may come from a nested block for which createsEnv==true (iff NOT targetBlock.createsEnv, because outermost blocks
    // take precedence). applies only to BreakControl and JSR instrucs; Continue is also multi-block but implements custom restore logic.
    public static void resolveMultiBlockRestore(BlockControl blockCtrl) {
        BlockContext currBlock = blockCtrl.startBlock;
        do {
            Integer segOffset = currBlock.segOffset != null ? currBlock.segOffset : BlockContext.resolveSegOffset(currBlock);
            
            if (currBlock.createsEnv)
                blockCtrl.lexEnvRestore = segOffset;
            
            if (currBlock === blockCtrl.targetBlock) {
                blockCtrl.stackRestore = segOffset;
                break;
            } else
                currBlock = currBlock.outerBlock;
            
        } while (true);
    }
    
    // resolves the stackLexEnv and stackRestore offsets for instrucs that only need to restore to the point immediately before instantiation of the 
    // targetBlock (no nested blocks), because their starting state is guaranteed at some point of execution within the targetBlock (but NOT in any
    // nested block), possibly including the time immediately subsequent to the targetBlock's instantiation (i.e. at the earliest).
    public static void resolveSingleBlockRestore(BlockControl blockCtrl) {
        BlockContext targetBlock = blockCtrl.targetBlock;
        Integer segOffset = targetBlock.segOffset != null ? targetBlock.segOffset : BlockContext.resolveSegOffset(targetBlock);
        
        if (targetBlock.createsEnv)
            blockCtrl.lexEnvRestore = segOffset;
        
        blockCtrl.stackRestore = segOffset;
    }
    
    // !! this assumes blockCtrl.targetBlock is a deferring block (i.e. tryBlock or catchBlock) that will store lexEnv via STOLEX
    public static void resolveDeferringBlockFullRestore(BlockControl blockCtrl) {
        BlockContext targetBlock = blockCtrl.targetBlock;
        Integer segOffset = targetBlock.segOffset != null ? targetBlock.segOffset : BlockContext.resolveSegOffset(targetBlock);
        // unconditionally restore lexEnv to that stored for the deferring targetBlock:
        blockCtrl.lexEnvRestore = segOffset;
        blockCtrl.stackRestore = segOffset;
    }
    
    // standard attributes:
    // intVal      ; resolved to the target jump address in resolvePass2()
    // strVal      ; the target label, if any (implicit empty label if null). set during parse.
    //
    // block control attributes:
    // startBlock  ; the starting point. this instruc will be dispatched sometime during the execution of this startBlock, while it is active (i.e.
    //               we can assert that none of its nested blocks are currently active), including possibly the time immediately following the 
    //               startBlock's instantiation. note that startBlock is not necessarily the block that directly hosts this break instruc, i.e. if
    //               it's been guarded by 1 or more JSR instrucs. set during parse.
    // targetBlock ; the switch block, loop block, or plain block that is targeted by this break stmt. this block will be rest'd as a result of this
    //               break instruc.
    //
    // implementation (same as continue):
    // <Standard Block Restore>
    // active.next = this.intVal
    public class BreakControl extends BlockControl {
        public BreakControl() {
            this.opCode = OP_BRK;
        }
        
        public override void resolvePass2() {
            resolveMultiBlockRestore(this);
            this.intVal = targetBlock.endAddr;
        }
        
        public override String toString() {
            return 'BRK[' + intVal + ']' + (strVal != '' ? '[' + strVal + ']' : '');
        }
    }
    
    // standard attributes:
    // intVal      ; resolved to the target jump address in resolvePass2() 
    // strVal      ; the target label, if any (implicit empty label if null). set during parse.
    //
    // block control attributes:
    // startBlock  ; the starting point. this instruc will be dispatched sometime during the execution of this startBlock, while it is active (i.e.
    //               we can assert that none of its nested blocks are currently active), including possibly the time immediately following the 
    //               startBlock's instantiation. note that startBlock is not necessarily the block that directly hosts this break instruc, i.e. if
    //               it's been guarded by 1 or more JSR instrucs. set during parse.
    // targetBlock ; the loop block that is targeted by this continue stmt. unlike with the break instruc, this block will NOT be rest'd as a result
    //               of this continue instruc -- however, any active nested blocks are guaranteed to be rest'd.
    //
    // implementation (same as break):
    // <Standard Block Restore>
    // active.next = this.intVal
    public class ContinueControl extends BlockControl {
        public ContinueControl() {
            this.opCode = OP_CONT;
        }
        
        public override void resolvePass2() {
            BlockContext currBlock = startBlock;
            // continue differs from break in that continue only restores up to (and including) the penultimate block before the target, while break
            // restores right up to (and including) the target block:
            while (currBlock !== targetBlock) {
                Integer segOffset = currBlock.segOffset != null ? currBlock.segOffset : BlockContext.resolveSegOffset(currBlock);
                
                if (currBlock.createsEnv)
                    lexEnvRestore = segOffset;
                
                // use the segmented stack offset from the penultimate-to-target block:
                stackRestore = segOffset;
                currBlock = currBlock.outerBlock;
            }
            
            // the parser must set continueAddr for any block that can be targeted by a continue (i.e. loop blocks):
            this.intVal = targetBlock.continueAddr;
        }
        
        public override String toString() {
            return 'CONT[' + intVal + ']' + (strVal != '' ? '[' + strVal + ']' : '');
        }
    }
    
    // Jump to SubRoutine
    // jump to a finally block from a try block, catch block, or implicit catch
    //
    // standard attributes:
    // intVal      ; resolved to the target jump address (i.e. the start of the finally block) in resolvePass2(). 
    //               !! note the intVal jump addr will remain null if no finally block is parsed -- this causes a bypass of the JSR's jump logic, but
    //               not of its block restores nor its value-currying, which are still necessary. 
    // boolVal     ; flags whether this JSR should curry a value (for either a return or throw). set to true only for 2 scenarios:
    //                 1. for JSR's that guard a return instruc
    //                 2. for the implicit catch's JSR, guarding a THROW. note that the implicit catch (a JSR and a THROW) is logically situated
    //                    between the catch & finally blocks, and is serialized regardless of which of these blocks are present
    //             ; set during parse.
    //
    // block control attributes:
    // startBlock  ; the starting point for this JSR, compensated for by any prior guarding JSR's. set during parse.
    // targetBlock ; the deferring block (tryBlock or catchBlock) that is targeted by this JSR. set during parse.
    //
    // custom attributes:
    // returnAddr  ; points to the next instruc that should be executed after returning via RSR. set during parse in aggregateUp().
    //
    // implementation:
    // let curryValFlag = this.boolVal == true
    // let jumpAddr = this.intVal
    // let curryVal = undefined
    // if curryValFlag
    //     set curryVal = stack.top ; store the curry value before we do a block restore
    // <Standard Block Restore>
    // if jumpAddr != null
    //     stack.add(this.returnAddr) ; finally block reserved stack slots: [<returnAddr>, <curryValFlag>, <curryVal>]
    //     stack.add(curryValFlag)
    //     stack.add(curryVal)
    //     active.next = jumpAddr
    // else if curryValFlag
    //     stack.add(curryVal) ; if we bypassed the jump then we still need to curry the value to the nextAddr instruc
    //     ; technically, we can skip setting active.next = this.nextAddr, because that's implicit in the vm's dispatch model
    public virtual class JSR extends BlockControl {
        public Integer returnAddr;
        
        public JSR() {
            this.opCode = OP_JSR;
        }
        
        public virtual override void resolvePass2() {
            resolveMultiBlockRestore(this);
            // !! intVal will have been resolved and set by the parser
        }
        
        public virtual override String toString() {
            return 'JSR' + (intVal != null ? '[' + intVal + ']' : '') + '[' + returnAddr + '][' + boolVal + ']';
        }
    }
    
    // a special JSR that has been flagged as the start of an implicit-catch segment (2 instrucs: JSR_IC and THROW). this is necessary because an
    // implicit-catch may be entered from any nested block state of the corresponding try or catch blocks, and the lexEnv must be unconditionally
    // restored to that of the try/catch block's STOLEX (note that the lex & stack restore offsets are guaranteed to be the same for both try
    // and catch blocks of the same TryStatement). this differs from standard JSR, which conditionally restores lexEnv if any block between
    // startBlock and targetBlock (inclusive) has createsEnv==true -- and then only does so for the outermost such block, which may not necessarily
    // be the targetBlock. 
    // 
    // JSR_IC op-codes, attributes, and implementation are largely the same as JSR, with the following exceptions:
    //   1. the startBlock attribute is unused
    //   2. the targetBlock attribute will be set to either the tryBlock (TryStatement Layout II) or an explicit catchBlock (TryStatement Layouts
    //      I and III); note that try/catch blocks of the same TryStatement are interchangeable for the purpose of calculating block restores.
    //   2. resolvePass2() and toString() are overridden:
    public class JSR_IC extends JSR {
        public JSR_IC() {
            this.opCode = OP_JSR;
        }
        
        public override void resolvePass2() {
            resolveDeferringBlockFullRestore(this);
            // !! intVal will have been resolved and set by the parser
        }
        
        public override String toString() {
            return super.toString().replaceFirst('^JSR', 'JSR_IC');
        }
    }
    
    // Instantiates a catch-block
    //
    // standard attributes:
    // intVal      ; an int flag that represents a very simple Declaration Binding Instantiation sub-instruc for instantiating this catch block.
    //               resolved in pass2, its possible values & meanings are:
    //                 0 => error var is not referenced; we may ignore the thrown value atop the stack
    //                 1 => write the thrown value (atop stack) into the 2nd stack slot (i.e. the 1st slot after the reserved lexEnv slot)
    //                 2 => create a new lexEnv and put the thrown value (atop stack) into it under the name of this.strVal
    // strVal      ; the processed lexeme of the error var token, set by parser
    //
    // block control attributes:
    // startBlock  ; unused
    // targetBlock ; the catch-block; we need to examine its aggregations to determine the Declaration Binding Instantiation sub-instruc. note that
    //               a catch-block block is guaranteed to store its lexEnv at the same stack index as its corresponding try-block, so we don't need
    //               a reference to the try-block to resolve block restoration. set by parser.
    //
    // implementation:
    // let caughtVal = stack[top] ; thrown value is guaranteed to be atop the stack
    // <Standard Block Restore> ; restore to the point immediately before instantiation of this try/catch
    // stack.add(active.lexEnv) ; store the lexEnv (1st stack slot)
    // let subInstruc = this.intVal
    // if subInstruc > 0 ; 0 indicates an unused error var
    //     if subInstruc == 1 ; the error var has been converted to a local stack var (2nd stack slot)
    //         stack.add(caughtVal)
    //     else ; else we must create a new lexical environment for the error var
    //         let newEnv = new DeclarativeEnv(active.lexEnv)
    //         active.lexEnv = newEnv
    //         newEnv.defineMutableBinding(this.strVal, caughtVal)
    public class CatchStart extends BlockControl {
        public CatchStart() {
            this.opCode = OP_CATCH;
        }
        
        public override void resolvePass2() {
            // computes restoration to the point immediately before the corresponding tryBlock's instantiation (including unconditional lexEnv
            // restore).
            // !! note that we use resolvedDeferringBlockRestore instead of resolveSingleBlockRestore, because the former forces a lexEnv restore to
            // the deferring block's stored lexEnv -- this is necessary for the CATCH and implicit-catch JSR, since they may be entered from any
            // block-nesting state from the tryBlock or catchBlock (due to the nature of THROW):
            resolveDeferringBlockFullRestore(this);
            // determine the Declaration Binding Instantiation sub-instruc:
            if (targetBlock.createsEnv) {
                intVal = 2;
            } else if (targetBlock.stackRefsByName != null && targetBlock.stackRefsByName.containsKey(strVal)) {
                intVal = 1;
                for (Instruc.EnvRef ref: targetBlock.stackRefsByName.get(strVal)) {
                    // !! mutate to a stack ref opCode; is this ref is a lhs assignee then it's always valid because the error var is writable:
                    ref.opCode = OP_STKREF;
                    // assignment is allowed (not necessary to set here since boolVal is already true from pass1 if this is a lhs assignee ref):
                    //ref.boolVal = true;
                    // resolve the stack ref's stack offset (relative to the segment's start index); remember that the prior block's saved lexEnv is
                    // at offset=0 and the error val is at offset=1, so we must add 1 to this catchBlock's block offset to determine the error var's
                    // stack slot:
                    ref.intVal = 1 
                            + (targetBlock.segOffset != null ? targetBlock.segOffset : BlockContext.resolveSegOffset(targetBlock));
                }
            } else {
                intVal = 0;
            }
        }
        
        public override String toString() {
            return 'CATCH';
        }
    }
    
    // Return from SubRoutine
    // Jumps from the finally block to a return address (1st reserved stack slot for current block) inside a corresponding try block, catch block, or
    // implicit catch.
    //
    // attributes:
    // startBlock  ; unused
    // targetBlock ; the finally-block to be terminated by this RSR. set during parse.
    //
    // implementation:
    // let returnAddr = stack[this.stackRestore] ; 1st reserved stack slot for finally block
    // let curryValFlag = stack[this.stackRestore + 1] ; 2nd reserved stack slot
    // if curryValFlag == true
    //     let curryVal = stack[this.stackRestore + 2] ; 3rd reserved stack slot
    //     <Standard Block Restore>
    //     stack.add(curryValFlag) ; post the curryVal back to the stack for the instruc at returnAddr
    // else
    //     <Standard Block Restore>
    // active.next = returnAddr
    public class RSR extends BlockControl {
        public Integer returnAddr;
        
        public RSR() {
            this.opCode = OP_RSR;
        }
        
        public override void resolvePass2() {
            // !! note that since an RSR is always the last instruc in a finally block and is guaranteed to be directly contained by it, it cannot
            // be contained by an inner block that creates a lexEnv nor has stack vars -- hence, we may assert that lexEnvRestore==null:
            //stackRestore = targetBlock.segOffset != null ? targetBlock.segOffset : BlockContext.resolveSegOffset(targetBlock);
            resolveSingleBlockRestore(this);
        }
        
        public override String toString() {
            return 'RSR';
        }
    }
    
    // Simple single-block restore; restores the stack and lexEnv to the state immediately prior to the targetBlock's invocation. Used to terminate
    // a with-block.
    //
    // attributes:
    // startBlock  ; unused
    // targetBlock ; the block to be rest'd. set during parse.
    //
    // implementation:
    // <Standard Block Restore>
    public class RestBlock extends BlockControl {
        public RestBlock() {
            this.opCode = OP_RESTBLOK;
        }
        
        public override void resolvePass2() {
            resolveSingleBlockRestore(this);
        }
        
        public override String toString() {
            return 'RESTBLOK';
        }
    }
    
    // this instruc assumes the value atop the stack is an instance of RuntimeException
    //
    // implementation:
    // TODO: flesh out full implementation...
    // throw (RuntimeException) stack[top]
    public class ThrowErr extends Instruc {
        public ThrowErr() {
            this.opCode = OP_THROW;
        }
        
        public virtual override String toString() {
            return 'THROW';
        }
    }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    // attributes:
    // intVal ; set to the addr to jump to if the enumVal is null or undefined (i.e. the enum block's REST_BLOCK.addr, 1 slot before its endAddr)
    //
    // implementation:
    // let enumVal = stack[top] ; the enum loop's <objExpr> should result in the object value atop the stack (in the block's 1 reserved stack slot)
    // if enumVal == null || enumVal == Utils.NUL
    //     active.addr = this.intVal
    //     continue ; continue the vm loop
    //
    // let propList = new String[0]
    // let currObj = Utils.toObject(enumVal)
    //
    // do
    //     currObj.enumerateOwn(propList) ; note we've discarded the propToOwner map 2nd parameter
    //     currObj = currObj.proto
    // while (currObj != null)
    //
    // stack[top] = propList ; replace the object value with is serialized list of properties
    public class EnumStart extends Instruc {
        public EnumStart() {
            this.opCode = OP_ENUM;
        }
        
        public override String toString() {
            return 'ENUM';
        }
    }
    
    // attributes:
    // intVal ; set to the addr to jump to if the propList is empty (i.e. the enum block's REST_BLOCK.addr, 1 slot before its endAddr)
    //
    // implementation:
    // let propList = stack[top - 1] ; the stack is: [... <propList> <lhsRef>], where <propList> occupies the enumBlock's 1 reserved stack slot
    // if propList.size() == 0
    //     active.addr = this.intVal ; goto the REST_BLOCK, which will cleanup the <propList> and <lhsRef> left on the stack
    //     continue ; continue the vm loop
    //
    // let p = propList.remove(0)
    // stack.add(p) ; this puts the rhs-value atop the stack so we'll have: [... <propList> <lhsRef> <rhsValue>]
    public class EnumNext extends Instruc {
        public EnumNext() {
            this.opCode = OP_ENUMNXT;
        }
        
        public override String toString() {
            return 'ENUMNXT';
        }
    }
    
    // implementation:
    //
    // let val = stack.remove(top)
    // let obj = Utils.toObject(val)
    // let newEnv = new ObjectEnv(active.lexEnv, obj)
    // stack.add(active.lexEnv) ; STOLEX equivalent
    // active.lexEnv = newEnv
    public class WithStart extends Instruc {
        public WithStart() {
            this.opCode = OP_WITH;
        }
        
        public override String toString() {
            return 'WITH';
        }
    }
    
    // Creates a new empty plain object for an object literal, and pushes it atop the stack.
    // 
    // Impl:
    // stack.add(new PlainObject()) ; create an empty obj and push it atop the stack
    public class ObjectLit extends Instruc {
        public ObjectLit() {
            this.opCode = OP_OBJLIT;
        }
        
        public virtual override String toString() {
            return 'OBJLIT';
        }
    }
    
    // Adds a data property, with value, to the given property name on the outstanding object literal.
    // 
    // Impl:
    // PlainObject objLit = (PlainObject) stack[top - 1];
    // PropDesc prop = PropDesc.DataAllPrivsHasValue.clone();
    // prop.value = stack.remove(top);
    // objLit.defineOwnProperty(op.strVal, prop);
    public class ObjectLitProp extends Instruc {
        public ObjectLitProp(Lexer2.Token loc, String propName) {
            this.opCode = OP_OBJPROP;
            this.loc = loc;
            this.strVal = propName;
        }
        
        public virtual override String toString() {
            return 'OBJPROP[' + strVal + ']';
        }
    }
    
    // Adds an accessor [[Get]] aspect to the given property name on the outstanding object literal.
    // 
    // Impl:
    // PlainObject objLit = (PlainObject) stack[top - 1];
    // PropDesc prop = PropDesc.AccessorAllPrivs.clone();
    // CodeContext.Function code = (CodeContext.Function) stack.remove(top);
    // prop.getter = new MFunction(ctx, active.lexEnv, code);
    // objLit.defineOwnProperty(code.name, prop);
    public class ObjectLitGet extends Instruc {
        public ObjectLitGet(CodeContext.Function getCode) {
            this.opCode = OP_OBJGET;
            this.objVal = getCode;
        }
        
        public virtual override String toString() {
            return 'OBJGET[' + strVal + ']';
        }
    }
    
    // Adds an accessor [[Set]] aspect to the given property name on the outstanding object literal.
    // 
    // Impl:
    // PlainObject objLit = (PlainObject) stack[top - 1];
    // PropDesc prop = PropDesc.AccessorAllPrivs.clone();
    // prop.setter = (CodeContext.Function) stack.remove(top);
    // objLit.defineOwnProperty(prop.setter.name, prop);
    public class ObjectLitSet extends Instruc {
        public ObjectLitSet(CodeContext.Function setCode) {
            this.opCode = OP_OBJSET;
            this.objVal = setCode;
        }
        
        public virtual override String toString() {
            return 'OBJSET[' + strVal + ']';
        }
    }
    
    // Creates a raw Apex array to hold the elements; the Object[] will be converted into an ArrayObject upon the ARREND. each element must be either
    // a valid ECMAScript value or an Elision instance.
    // 
    // Impl:
    // stack.add(new Object[])
    public class ArrayLit extends Instruc {
        public ArrayLit() {
            this.opCode = OP_ARRLIT;
        }
        
        public virtual override String toString() {
            return 'ARRLIT';
        }
    }
    
    // Impl:
    // ((Object[]) stack[top - 1]).add(stack.remove(top));
    public class ArrayLitAdd extends Instruc {
        public ArrayLitAdd(Lexer2.Token loc) {
            this.opCode = OP_ARRADD;
            this.loc = loc;
        }
        
        public virtual override String toString() {
            return 'ARRADD';
        }
    }
    
    // Impl:
    // stack[top] = new ArrayObject((Object[]) stack[top]);
    public class ArrayLitEnd extends Instruc {
        public ArrayLitEnd(Lexer2.Token loc) {
            this.opCode = OP_ARREND;
            this.loc = loc;
        }
        
        public virtual override String toString() {
            return 'ARREND';
        }
    }
    
    // impl: see vm
    public class ArgStart extends Instruc {
        public ArgStart() {
            this.opCode = OP_ARGV;
        }
        
        public virtual override String toString() {
            return 'ARGV';
        }
    }
    
    // impl: see vm
    public class ArgAdd extends Instruc {
        public ArgAdd() {
            this.opCode = OP_ARGVADD;
        }
        
        public virtual override String toString() {
            return 'ARGVADD';
        }
    }
    
    public class ConstructorDispatch extends Instruc {
        // non-null if this constructor is launching from a reference (common case); in that case it must be an instance of ENVNEW/PROPNEW/DPROPNEW:
        public Instruc refOp;
        
        public ConstructorDispatch(Lexer2.Token loc, Instruc refOp) {
            this.opCode = OP_NEW;
        }
        
        public virtual override String toString() {
            return 'NEW';
        }
    }
    
    public static final Integer TCE_CANDIDATE_BIT = 1;
    public static final Integer DIRECT_CALL_EVAL_BIT = 2;
    
    // attributes:
    // callProps is a bitfield that may be null or 0 or may combine the TCE_CANDIDATE_BIT (Tail Call Elimination) and DIRECT_CALL_EVAL_BIT
    public class CallDispatch extends Instruc {
        // non-null if this call is launching from a reference (common case); in that case it must be an instance of ENVCALL/PROPCALL/DPROPCALL:
        public Instruc refOp;
        
        public CallDispatch(Lexer2.Token loc, Instruc refOp, Integer callProps) {
            this.opCode = OP_CALL;
            this.refOp = refOp;
            this.intVal = callProps;
        }
        
        public virtual override String toString() {
            return 'CALL';
        }
    }
    
    // replicates the top value of the stack (stack size is increased by 1)
    public class Copy extends Instruc {
        public Copy() {
            this.opCode = OP_CPY;
        }
        
        public override String toString() { return 'CPY'; }
    }
    
    // replicates the penultimate value of the stack so that the stack size is increased by 1, and stack[top - 1] == stack[top - 2]
    public class CopyPen extends Instruc {
        public CopyPen() {
            this.opCode = OP_CPYPEN;
        }
        
        public override String toString() { return 'CPYPEN'; }
    }
    
    // stack.remove(top)
    public class Pop extends Instruc {
        public Pop() {
            this.opCode = OP_POP;
        }
        
        public override String toString() { return 'POP'; }
    }
    
    // stack.remove(top - 1)
    public class PopPen extends Instruc {
        public PopPen() {
            this.opCode = OP_POPPEN;
        }
        
        public override String toString() { return 'POPPEN'; }
    }
    
    // Stack is expected to be [… <lhsRef> <rhsVal>]
    // PUT is expected to result in [… <rhsVal> <anyRefOrVal>], whether or not is dispatched a set-accessor (note the swap). However, PUT must
    // always be followed by a POP (compiler ensures this). Therefore, the PUT implementation may choose (in the name of improved efficiency) to do
    // the stack pop itself and bypass the subsequent POP via: addr += 2, continue (e.g. in cases where the reference is a stack ref or a
    // DeclarativeEnv base). In cases of an ObjectEnv or PlainObject reference base, the stack swap should be performed before the
    // [[PutValue]](<lhsRef>, <rhsVal>) invocation, so that the <lhsRef> will be atop the stack to receive any set-accessor return value (if a
    // set-accessor is indeed dispatched), and subsequently to be POP'd thus leaving the stack in the desired result state: [… <rhsVal>].
    // See vm for full impl.
    //
    // opCode is mutated to IMMUT in cases where this PUT is associated to a STKREF for an immutable binding
    //
    // Attribs:
    // strVal - populated only when the opCode has been mutated to IMMUT; in that case it holds the original environment reference's variable name,
    //     which should be used to provide a better message for the thrown TypeError (strict mode).
    public class Put extends Instruc {
        public Put(Lexer2.Token loc) {
            this.opCode = OP_PUT;
            this.loc = loc;
        }
        
        public override String toString() { return opCode == OP_IMMUT ? 'IMMUT' : 'PUT'; }
    }
    
    // !! note that we don't need LogicalOr/LogicalAnd instrucs...
    
    public class Multiply extends Instruc {
        public Multiply() {
            this.opCode = OP_MULT;
        }
        
        public override String toString() { return 'MULT'; }
    }
    
    public class Divide extends Instruc {
        public Divide() {
            this.opCode = OP_DIV;
        }
        
        public override String toString() { return 'DIV'; }
    }
    
    public class Modulus extends Instruc {
        public Modulus() {
            this.opCode = OP_MOD;
        }
        
        public override String toString() { return 'MOD'; }
    }
    
    public class Add extends Instruc {
        public Add() {
            this.opCode = OP_ADD;
        }
        
        public override String toString() { return 'ADD'; }
    }
    
    // version of Add when the 2 operands are guaranteed to both be numbers:
    public class AddNum extends Instruc {
        public AddNum() {
            this.opCode = OP_ADDNUM;
        }
        
        public override String toString() { return 'ADDNUM'; }
    }
    
    public class Subtract extends Instruc {
        public Subtract() {
            this.opCode = OP_SUB;
        }
        
        public override String toString() { return 'SUB'; }
    }
    
    public class BitOr extends Instruc {
        public BitOr() {
            this.opCode = OP_BTOR;
        }
        
        public override String toString() { return 'BTOR'; }
    }
    
    public class BitXor extends Instruc {
        public BitXor() {
            this.opCode = OP_BTXOR;
        }
        
        public override String toString() { return 'BTXOR'; }
    }
    
    public class BitAnd extends Instruc {
        public BitAnd() {
            this.opCode = OP_BTAND;
        }
        
        public override String toString() { return 'BTAND'; }
    }
    
    public class LeftShift extends Instruc {
        public LeftShift() {
            this.opCode = OP_LSHFT;
        }
        
        public override String toString() { return 'LSHFT'; }
    }
    
    public class RightShift extends Instruc {
        public RightShift() {
            this.opCode = OP_RSHFT;
        }
        
        public override String toString() { return 'RSHFT'; }
    }
    
    public class URightShift extends Instruc {
        public URightShift() {
            this.opCode = OP_URSHFT;
        }
        
        public override String toString() { return 'URSHFT'; }
    }
    
    // abstract equality
    public class Equals extends Instruc {
        public Equals(Lexer2.Token loc) {
            this.opCode = OP_EQ;
            this.loc = loc;
        }
        
        public override String toString() { return 'EQ'; }
    }
    
    // abstract inequality
    public class NotEquals extends Instruc {
        public NotEquals(Lexer2.Token loc) {
            this.opCode = OP_NEQ;
            this.loc = loc;
        }
        
        public override String toString() { return 'NEQ'; }
    }
    
    public class StrictEquals extends Instruc {
        public StrictEquals(Lexer2.Token loc) {
            this.opCode = OP_STEQ;
            this.loc = loc;
        }
        
        public override String toString() { return 'STEQ'; }
    }
    
    public class StrictNotEquals extends Instruc {
        public StrictNotEquals(Lexer2.Token loc) {
            this.opCode = OP_STNEQ;
            this.loc = loc;
        }
        
        public override String toString() { return 'STNEQ'; }
    }
    
    public class InOp extends Instruc {
        public InOp(Lexer2.Token loc) {
            this.opCode = OP_IN;
            this.loc = loc;
        }
        
        public override String toString() { return 'IN'; }
    }
    
    public class InstanceofOp extends Instruc {
        public InstanceofOp(Lexer2.Token loc) {
            this.opCode = OP_INSTOF;
            this.loc = loc;
        }
        
        public override String toString() { return 'INSTOF'; }
    }
    
    // The stack top is guaranteed to be a number value.
    // Impl:
    // stack[top] = (Double) stack[top] + op.intVal;
    public class Inc extends Instruc {
        public Inc(Integer incValue) {
            this.opCode = OP_INC;
            this.intVal = incValue;
        }
        
        public virtual override String toString() {
            return intVal > 0 ? 'INC' : 'DEC';
        }
    }
    
    // The stack top is guaranteed to be a boolean value.
    public class LogicalNot extends Instruc {
        public LogicalNot() {
            this.opCode = OP_LOGNOT;
        }
        
        public override String toString() { return 'LOGNOT'; }
    }
    
    // The stack top is guaranteed to be an int32 value.
    public class BitNot extends Instruc {
        public BitNot() {
            this.opCode = OP_LOGNOT;
        }
        
        public override String toString() { return 'BITNOT'; }
    }
    
    // The stack top is guaranteed to be a number value.
    public class NumNegate extends Instruc {
        public NumNegate() {
            this.opCode = OP_NEG;
        }
        
        public override String toString() { return 'NUMNEG'; }
    }
    
    public class DeleteBinding extends Instruc {
        public DeleteBinding(Lexer2.Token loc) {
            this.opCode = OP_DEL;
            this.loc = loc;
        }
        
        public override String toString() { return 'DEL'; }
    }
    
    // The stack top is guaranteed to be a non-ref value. Examines this value and replaces the stack top with a string representing its data type.
    public class TypeOf extends Instruc {
        public TypeOf() {
            this.opCode = OP_TYPEOF;
        }
        
        public override String toString() { return 'TYPEOF'; }
    }
    
    public static String toString(Instruc[] instrucs) {
        String buffer = '';
        for (Instruc ins: instrucs) {
            if (buffer.length() > 0)
                buffer += ' ';
            
            buffer += ins.toString();
        }
        return buffer;
    }
    
    // Maps a token id -- representing a compound assignment operator, e.g. '+=' -- to its corresponding binary op Instruc prototype and expected
    // result valueType
    // !! ASSIGN_MODULUS must have the largest id value of the compound assignment tokens:
    public static OpInfo[] CompoundAssignTable = new OpInfo[Lexer2.ASSIGN_MODULUS + 1];
    static {
        CompoundAssignTable[Lexer2.ASSIGN_MULTIPLY] = new OpInfo(new Multiply(), Parser2.NUM_VAL);
        CompoundAssignTable[Lexer2.ASSIGN_DIVIDE] = new OpInfo(new Divide(), Parser2.NUM_VAL);
        CompoundAssignTable[Lexer2.ASSIGN_MODULUS] = new OpInfo(new Modulus(), Parser2.NUM_VAL);
        CompoundAssignTable[Lexer2.ASSIGN_PLUS] = new OpInfo(new Add(), Parser2.NUM_OR_STR_VAL);
        CompoundAssignTable[Lexer2.ASSIGN_MINUS] = new OpInfo(new Subtract(), Parser2.NUM_VAL);
        CompoundAssignTable[Lexer2.ASSIGN_BIT_OR] = new OpInfo(new BitOr(), Parser2.INT32_VAL);
        CompoundAssignTable[Lexer2.ASSIGN_BIT_XOR] = new OpInfo(new BitXor(), Parser2.INT32_VAL);
        CompoundAssignTable[Lexer2.ASSIGN_BIT_AND] = new OpInfo(new BitAnd(), Parser2.INT32_VAL);
        CompoundAssignTable[Lexer2.ASSIGN_LEFT_SHIFT] = new OpInfo(new LeftShift(), Parser2.INT32_VAL);
        CompoundAssignTable[Lexer2.ASSIGN_RIGHT_SHIFT] = new OpInfo(new RightShift(), Parser2.INT32_VAL);
        CompoundAssignTable[Lexer2.ASSIGN_URIGHT_SHIFT] = new OpInfo(new URightShift(), Parser2.NUM_VAL);
    }
    
    public class OpInfo {
        public Instruc instrucProto;
        public Integer resultValueType;
        
        OpInfo(Instruc instrucProto, Integer resultValueType) {
            this.instrucProto = instrucProto;
            this.resultValueType = resultValueType;
        }
    }
}