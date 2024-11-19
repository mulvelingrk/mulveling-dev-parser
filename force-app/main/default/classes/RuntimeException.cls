/*
 * Mike Ulveling
 */
global class RuntimeException extends Exception {
    // non-null in the case of ParseException or ApexError; these should be used to provide accurate source code locations:
    Exception nativeCause;
    
    // the source code location that should (if possible) correspond to where this exception thrown. may be null:
    public Lexer2.Token loc;
    // a shallow clone of the host vm's call stack at the time the exception was thrown -- note that ParseExceptions occur before creation of the
    // host context & vm, and thus will have a null callStack (but they should have a non-null loc):
    public Frame[] callStack;
    // the thrown value:
    public Object thrown;
    
    public Context lastHandledBy;
    
    // !! "thrown" should be a valid ECMAScript value; it should never be an instance of Exception:
    public RuntimeException(Context ctx, Object thrown) {
        this.thrown = thrown;
        if (thrown instanceof Error)
            ((Error) thrown).throwWrapper = this;
        
        this.loc = ctx.vm != null ? (ctx.vm.op != null ? ctx.vm.op.loc : null) : null;
        // compile the full vm list, from this vm to root, in reverse order (root context is last):
        Context[] activeMachines = new Context[]{ ctx };
        while ((ctx = ctx.parent) != null)
            activeMachines.add(ctx);
        
        // compile the full call stack consisting of the active frames from the root context, all the way down to the active frames in this context:
        this.callStack = new Frame[]{};
        for (Integer i=activeMachines.size() - 1; i >= 0; i--)
            this.callStack.addAll(activeMachines[i].vm.calls);
    }
    
    public static RuntimeException newSyntaxError(Context ctx, ParseException parseExcep) {
        SyntaxError error = new SyntaxError(ctx, parseExcep.getMessage());
        RuntimeException re = new RuntimeException(ctx, error);
        re.loc = parseExcep.loc;
        re.nativeCause = parseExcep;
        return re;
    }
    
    global static RuntimeException newApexError(Context ctx, Exception apexExcep) {
        ApexError error = new ApexError(ctx, apexExcep.getMessage());
        RuntimeException re = new RuntimeException(ctx, error);
        re.nativeCause = apexExcep;
        return re;
    }
}