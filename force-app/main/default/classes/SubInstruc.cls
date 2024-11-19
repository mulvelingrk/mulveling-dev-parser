/*
 * Mike Ulveling
 */
public class SubInstruc {
    // op codes for the various sub-instruc types:
    public static final Integer OP_CREATE_ENV_OBJ     = 0;
    public static final Integer OP_INHERIT_ENV        = 1;
    public static final Integer OP_STACK_ALLOC        = 2;
    public static final Integer OP_BIND_FUNCS         = 3;
    public static final Integer OP_BIND_PARAMS        = 4;
    public static final Integer OP_BIND_ARGUMENTS_OBJ = 5;
    public static final Integer OP_BIND_RECURSIVE_REF = 6;

    public static final Integer DEST_STACK = 0;
    public static final Integer DEST_ENV   = 1;
    
    // defines the instruc type:
    public Integer opCode;
    
    // for use by OP_STACK_ALLOC only:
    public Integer length;
    
    // for use by OP_BIND_FUNCS, OP_BIND_PARAMS, OP_BIND_ARGUMENTS_OBJ, and OP_BIND_RECURSIVE_REF; indicates whether the binding(s) should be defined
    // in the created environment record or in allocated stack slots:
    public Integer destination = DEST_ENV;
    
    // for use by CREATE_ENV_OBJ only:
    public Map<String, Object> uninitBindings; // binds all non-stack vars to an undefined default value
    public Set<String> immutables; // defines which non-stack vars are immutable (only "arguments" and recursive func ref can be)
    
    // for OP_BIND_FUNCS and OP_BIND_PARAMS, the rhsValueIndex references into the function decs or formal params arrays (respectively). this is the
    // first/rightmost value. the last/leftmost value is determined by the sum (rhsValueIndex + lhsOffset); note that this is the same as the
    // rightmost element in the case lhsOffset==0. when this sub-instruc is executed, it will copy the values -- in right-to-left order -- into the
    // same # of stack slots. the destination stack slots start at the segmented stack offset indicated by lhsOffset, and also proceed in right-to-
    // left fashion in sync with the values array:
    public Integer rhsValueIndex;
    public Integer rhsStackOffset;
    public Integer rhsSegOffset;
    // an integer less than or equal to 0 (since we're working from right-to-left); the # of values to be copied to the stack is: (-lhsOffset + 1)
    public Integer lhsOffset = 0;
    
    private SubInstruc(Integer opCode) {
        this.opCode = opCode;
    }
    
    public static final SubInstruc CREATE_ENV_OBJ     = new SubInstruc(OP_CREATE_ENV_OBJ);
    public static final SubInstruc INHERIT_ENV        = new SubInstruc(OP_INHERIT_ENV);
    public static final SubInstruc STACK_ALLOC        = new SubInstruc(OP_STACK_ALLOC);
    public static final SubInstruc BIND_FUNCS         = new SubInstruc(OP_BIND_FUNCS);
    public static final SubInstruc BIND_PARAMS        = new SubInstruc(OP_BIND_PARAMS);
    public static final SubInstruc BIND_ARGUMENTS_OBJ = new SubInstruc(OP_BIND_ARGUMENTS_OBJ);
    public static final SubInstruc BIND_RECURSIVE_REF = new SubInstruc(OP_BIND_RECURSIVE_REF);
}