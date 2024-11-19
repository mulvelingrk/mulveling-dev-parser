/*
 * Mike Ulveling
 */
global class EvalFunction extends Function {
    public EvalFunction(Context ctx) {
        super(ctx, 'eval', 1);
    }
    
    // this is used for indirect calls to eval:
    global override Object call(Context ctx, Object thisBinding, Object[] argv) {
        return EvalFunction.evalImpl(ctx, null, argv);
    }
    
    // !! if this is not for a direct call, then directCallingFrame must be passed in as null:
    public static Object evalImpl(Context ctx, Frame directCallingFrame, Object[] argv) {
        /*
        if (argv.size() == 0)
            return null;
        else if (!(argv[0] instanceof String))
            return argv[0];
        
        CodeContext.EvalCode evalCode;
        try {
            // 10.1.1 -- strict mode is inherited from the calling frame only in the case of a direct call; Parser2.parseEval will also incorporate a
            // "use strict" Directive Prologue into the resultant EvalCode's strict flag:
            Boolean inheritsStrict = directCallingFrame != null && directCallingFrame.strict;
            evalCode = Parser2.parseEvalCode((String) argv[0], inheritsStrict);
        } catch (ParseException e) {
            throw RuntimeException.newSyntaxError(ctx, e);
        }
        
        // 10.4.2 -- note that if this was not a direct call to eval, then directCallingFrame will be null:
        Context fork_ctx = ctx.clone();
        VirtualMachine fork_vm = new VirtualMachine(fork_ctx);
        if (directCallingFrame == null) {
            if (evalCode.strict) {
                Environment strictVarEnv = new DeclarativeEnv(ctx.globalEnv);
                new Frame.Eval(fork_ctx, evalCode, strictVarEnv, strictVarEnv, ctx.globalObj);
            } else
                // in this case, the eval code should act as if it is a global execution context 10.4.2[1.a.]:
                new Frame.Eval(fork_ctx, evalCode);
        } else {
            if (evalCode.strict) {
                Environment strictVarEnv = new DeclarativeEnv(directCallingFrame.lexEnv);
                new Frame.Eval(fork_ctx, evalCode, strictVarEnv, strictVarEnv, directCallingFrame.thisBinding);
            } else
                new Frame.Eval(fork_ctx, evalCode, directCallingFrame.varEnv, directCallingFrame.lexEnv, directCallingFrame.thisBinding);
        }
        
        return fork_vm.exec();
        */
        
        System.assert(false, 'not implemented');
        return null;
    }
}