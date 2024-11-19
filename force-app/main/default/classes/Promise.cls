/*
 * Mike Ulveling
 * 
 * TODO: Deprecated
 */
public abstract class Promise {
    // the frame (i.e. execution context) under which this promise was instantiated:
    public Frame hostFrame;
    
    public abstract void onNaturalCompletion(Context ctx);
    
    public abstract void onTryFinally();

    /*
    // the "val" param is used by "throw" and "return" completions (i.e. valued completions), but not "break" nor "continue" (pass null for targeted
    // completions):
    public abstract Boolean handleAbruptCompletion(Context ctx, Instruc.AbruptCompletion instruc, Object val);

    // !! this constructor will push this new instance atop the vm.promises stack:
    Promise(Context ctx) {
        VirtualMachine vm = ctx.vm;
        // the active frame become the host at the start of this promise:
        this.hostFrame = vm.active;
        vm.promises.add(this);
    }
    
    public class TryPromise extends Promise {
        // contains the relevant enclosing break & continue labels (inherited from Instruc.PromiseStart):
        Instruc.TryStart tryStart;
        // 0 => try block
        // 1 => catch block
        // 2 => finally block
        Integer state = 0;
        
        // an incoming abrupt completion event will become deferred under the following scenarios:
        //   * in try clause and a relevant return/break/continue is received
        //   * in try clause when there is NO catch clause and a throw is received -- note that a throw is unconditionally relevant to any TryPromise
        //     that receives it
        //   * in catch clause and a throw or a relevant return/break/continue is received
        //
        // a deferred event will be re-fired (i.e. injected into the host frame) upon the natural completion of this try stmt -- though note that
        // natural completion will not occur in the case of a custom finally clause that triggers its own abrupt completion event during execution;
        // in that case the deferred event is lost:
        Instruc.AbruptCompletion deferred;
        // deferredVal is relevant only to deferred "return" and "throw" completions; disregard for "break" and "continue" completions:
        Boolean deferredIsValued;
        Object deferredVal;
        
        // TRY_START
        // !! this call will push this new instance atop the vm.promises stack:
        public TryPromise(Context ctx, Instruc.TryStart tryStart) {
            super(ctx);
            this.tryStart = tryStart;
        }
        
        // TRY_FINALLY instruc -- guaranteed to be called for this try block; it is not bypassable:
        // TODO: consider making this an abstract base class method (in order to avoid the need for a TryPromise cast by the vm) that merely throws
        // an exception for instances other than TryPromise...
        public override void onTryFinally() {
            // cleanup the catch clause, if it was active -- i.e. reinstate the original LexicalEnvironment:
            if (state == 1) {
                hostFrame.lexEnv = hostFrame.lexEnv.parent;
            }
            state = 2;
        }
        
        // TRY_END instruc -- signals a "natural" end to the finally clause (whether custom or implicit). we can assume that this TryPromise is
        // currently atop the promises stack, and that this.hostFrame is active. a try stmt's TRY_END instruc can only be bypassed if a custom
        // finally clause causes an abrupt completion event:
        public override void onNaturalCompletion(Context ctx) {
            if (deferred != null) {
                // inject the deferred event instruc (and val, when necessary) into the vm:
                hostFrame.injected = deferred;
                if (deferredIsValued)
                    // we know that hostFrame will be active before, during, and immediately after this TRY_END instruc, so the vm's stack top will
                    // be the correct position to add upon here:
                    // !! this is one of the few times we'll put a RuntimeException instance onto the stack, in addition to the vm's 2 processing
                    // loop catch clauses: 
                    ctx.vm.stack.add(deferredVal);
            }
            // tear down this context:
            Promise[] promises = ctx.vm.promises;
            promises.remove(promises.size() - 1);
        }
        
        public override Boolean handleAbruptCompletion(Context ctx, Instruc.AbruptCompletion event, Object val) {
            VirtualMachine vm = ctx.vm;
            if (event.sid == Instruc.SID_THROW) {
                // if this thrown can be "caught" by a catch clause that hasn't yet been activated:
                if (state == 0 && tryStart.catchOffset != null) {
                    // activate the catch clause:
                    state = 1;
                    // the next iteration of the vm will start at the catch clause's first instruc:
                    hostFrame.next = tryStart.catchOffset;
                    // no state may carry forward from the stack:
                    for (Integer i=vm.stack.size() - 1; i >= hostFrame.stackOffset; i--)
                        vm.stack.remove(i);
                    
                    // if the thrown val is wrapped in a RuntimeException, then unwrap it:
                    if ((val instanceof RuntimeException) && val != null)
                        val = ((RuntimeException) val).thrown;
                        
                    // create and enact the error environment that defines the error variable -- it's mutable but not deletable:
                    hostFrame.lexEnv = DeclarativeEnv.newInstance(ctx, hostFrame.lexEnv, tryStart.errorIdent, val, true, false);
                    Frame[] calls = vm.calls;
                    // remove all frames atop this try stmt's host frame on the vm's call stack:
                    for (Integer i=calls.size() - 1; i > hostFrame.index; i--)
                        // this frame is now inactive, and should be cleaned up to free memory -- this frame is still referenced by the runtime
                        // exception's callStack, but the stack trace functionality does not require the values stack nor thisBinding:
                        calls.remove(i);
                    
                    // point the vm to the new active frame:
                    vm.active = calls[hostFrame.index];
                    // cancel the vm's default handling of throw (which is to throw a HaltingException):
                    return false;
                    
                // else, if this thrown can be deferred to the end of a finally clause that hasn't yet been activated:
                } else if (state < 2) {
                    // activate the finally clause:
                    state = 2;
                    // the next iteration of the vm will start at the finally clause's first instruc (whether custom or implicit); note that
                    // finallyOffset is guaranteed to be a non-null int value pointing to a TRY_FINALLY instruc:
                    hostFrame.next = tryStart.finallyOffset;
                    // no state may carry forward from the stack:
                    for (Integer i=vm.stack.size() - 1; i >= hostFrame.stackOffset; i--)
                        vm.stack.remove(i);
                    
                    // setup the thrown as a deferred event:
                    deferred = event;
                    deferredIsValued = true;
                    deferredVal = val;
                    Frame[] calls = ctx.vm.calls;
                    // remove all frames atop this try stmt's host frame on the vm's call stack:
                    for (Integer i=calls.size() - 1; i > hostFrame.index; i--)
                        // this frame is now inactive, and should be cleaned up to free memory -- this frame is still referenced by the runtime
                        // exception's callStack, but the stack trace functionality does not require the values stack nor thisBinding:
                        calls.remove(i);
                    
                    // point the vm to the new active frame:
                    vm.active = calls[hostFrame.index];
                    // cancel the vm's default handling of throw (which is to throw out a RuntimeException that will halt the vm):
                    return false;
                    // TODO: optimize for the case when we have no custom finally clause (tryStart.finallyOffset == null)...
                    
                // else, we must already be in the finally cause; tear down this context and continue the throw event's propagation up the promises/
                // calls stacks:
                } else {
                    // tear down this promise:
                    Promise[] promises = vm.promises;
                    Integer promisesLeft = promises.size() - 1;
                    promises.remove(promisesLeft);
                    // route the event to the next promise, if available:
                    if (promisesLeft > 0)
                        return promises[promisesLeft - 1].handleAbruptCompletion(ctx, event, val);
                    else
                        return true;
                }
            } else if (event.sid == Instruc.SID_RETURN) {
                // a return is only relevant to this context if the host frame is currently active:
                if (hostFrame === vm.active) {
                    // if we're currently in the try or catch clause, then activate the finally clause and defer this return event:
                    if (state < 2) {
                        // activate the finally clause:
                        state = 2;
                        // the next iteration of the vm will start at the finally clause's first instruc (whether custom or implicit):
                        hostFrame.next = tryStart.finallyOffset;
                        // no old state may carry forward from the stack:
                        for (Integer i=vm.stack.size() - 1; i >= hostFrame.stackOffset; i--)
                            vm.stack.remove(i);
                        // setup the return as a deferred event:
                        deferred = event;
                        deferredIsValued = true;
                        deferredVal = val;
                        // cancel the vm's default handling of return:
                        return false;
                        
                    // else, the finally clause must already be active and we should tear down this promise and then allow the vm to perform its
                    // usual handling:
                    } else {
                        vm.promises.remove(vm.promises.size() - 1);
                        return true;
                    }
                    
                // else, this return event is not relevant to this context (i.e. it belongs to a frame above this context's host frame on the call
                // stack); the vm may perform the usual RETURN handling logic -- i.e. pop the active frame and push its stack top onto the next
                // frame's stack:
                } else
                    return true;
                
            // else, it must be a break or continue event:
            } else {
                // a return is only relevant to this context if the host frame is currently active:
                if (hostFrame === vm.active) {
                    Set<String> enclosingLabels;
                    if (event.sid == Instruc.SID_BREAK)
                        enclosingLabels = tryStart.enclosingBreakLabels;
                    // else, it must be a continue event:
                    else
                        enclosingLabels = tryStart.enclosingContLabels;
                    
                    // the break/continue target label is only relevant to this context if this try stmt or an enclosing stmt (not to cross function
                    // boundaries) has a label that matches the event's target label (including the implicit empty label):
                    if (enclosingLabels.contains(event.strVal)) {
                        // if we're currently in the try or catch clause, then activate the finally clause and defer this break/continue event:
                        if (state < 2) {
                            // activate the finally clause:
                            state = 2;
                            // the next iteration of the vm will start at the finally clause's first instruc (whether custom or implicit):
                            hostFrame.next = tryStart.finallyOffset;
                            // no old state may carry forward from the stack:
                            for (Integer i=vm.stack.size() - 1; i >= hostFrame.stackOffset; i--)
                                vm.stack.remove(i);
                            // setup the return as a deferred event:
                            deferred = event;
                            deferredIsValued = false;
                            // cancel the vm's default handling of break/continue:
                            return false;
                            
                        // else, the finally clause must already be active and we should tear down this promise and then allow the vm to perform its
                        // default handling:
                        } else {
                            vm.promises.remove(vm.promises.size() - 1);
                            return true;
                        }
                        
                    // else, the target label is not relevant to this context; allow the vm its default handling:
                    } else
                        return true;
                    
                // if not relevant to this context, then allow the vm its default break/continue handling (i.e. jump to its specified segment
                // offset):
                } else
                    return true;
            }
            return null;
        }
    }
    
    public class WithPromise extends Promise {
     // contains the relevant enclosing break & continue labels (inherited from Instruc.PromiseStart):
        Instruc.WithStart withStart;
        
        // WITH_START:
        // !! this call will push this new instance atop the vm.promises stack:
        public WithPromise(Context ctx, Instruc.WithStart withStart, PlainObject objVal) {
            super(ctx);
            this.withStart = withStart;
            hostFrame.lexEnv = new ObjectEnv(hostFrame.lexEnv, objVal, true);
        }
        
        public override void onTryFinally() {
            System.assert(false, 'TRY_FINALLY instruction is not implemented by WithPromise');
        }
        
        // WITH_END -- the natural (non-abrupt) end of a "with" promise:
        public override void onNaturalCompletion(Context ctx) {
            // simply tear down this promise and reinstate the host frame's original lexical environment:
            Promise[] promises = ctx.vm.promises;
            promises.remove(promises.size() - 1);
            hostFrame.lexEnv = hostFrame.lexEnv.parent;
        }
        
        public override Boolean handleAbruptCompletion(Context ctx, Instruc.AbruptCompletion event, Object val) {
            VirtualMachine vm = ctx.vm;
            // a throw event is always relevant to this promise; since a throw crosses right over function boundaries, it always tears down any 
            // "with" promise that receives it and then continues to propagate the event up the promises stack:
            if (event.sid == Instruc.SID_THROW 
                    // a return is only relevant when this with stmt's host frame is active:
                    || event.sid == Instruc.SID_RETURN && hostFrame === vm.active) {
                // reinstate the host frame's original LexicalEnvironment:
                hostFrame.lexEnv = hostFrame.lexEnv.parent;
                // tear down this promise:
                Promise[] promises = vm.promises;
                Integer promisesLeft = promises.size() - 1;
                promises.remove(promisesLeft);
                // route the event to the next promise, if available:
                if (promisesLeft > 0)
                    return promises[promisesLeft - 1].handleAbruptCompletion(ctx, event, val);
                // else, fallthrough to return true...
                
            // break/continue is only relevant if the host frame is active and the target label is on a statement that encloses this promise's with-
            // stmt (without crossing function boundaries):
            } else if ((event.sid == Instruc.SID_BREAK || event.sid == Instruc.SID_CONTINUE) && hostFrame === vm.active) {
                Set<String> enclosingLabels;
                if (event.sid == Instruc.SID_BREAK)
                    enclosingLabels = withStart.enclosingBreakLabels;
                // else, it must be a continue event:
                else
                    enclosingLabels = withStart.enclosingContLabels;
                
                if (enclosingLabels.contains(event.strVal)) {
                    // reinstate the host frame's original LexicalEnvironment:
                    hostFrame.lexEnv = hostFrame.lexEnv.parent;
                    // tear down this promise:
                    Promise[] promises = vm.promises;
                    Integer promisesLeft = promises.size() - 1;
                    promises.remove(promisesLeft);
                    // route the event to the next promise, if available:
                    if (promisesLeft > 0)
                        return promises[promisesLeft - 1].handleAbruptCompletion(ctx, event, val);
                    // else, fallthrough to return true...
                }
                // else, fallthrough to return true...
            }
            // if the event was not relevant to this with context, OR we purposely fell through to here, then we allow the vm to perform its default
            // handling:
            return true;
            return null;
        }
    }
    
    public class EnumPromise extends Promise {
        // contains the relevant enclosing break & continue labels (inherited from Instruc.PromiseStart):
        public Instruc.EnumStart enumStart;
        // the object whose properties we're enumerating:
        public PlainObject objVal;

        // the serialization of objVal's enumerable properties -- including those found up the prototype chain:
        public String[] enumList;
        public Map<String, PlainObject> nameToOwner;
        
        // iterator for enumList:
        public Integer next = 0;
        
        // ENUM_START:
        // !! this call will push this new instance atop the vm.promises stack:
        public EnumPromise(Context ctx, Instruc.EnumStart enumStart, PlainObject objVal) {
            super(ctx);
            this.enumStart = enumStart;
            this.objVal = objVal;
            
            // serialize all properties -- across the full proto chain -- that are non-masked and enumerable at this time; as the vm iterates through
            // these results it'll re-check each property, after the 1st, to determine whether it's been deleted or made non-enumerable during a
            // prior iteration:
            this.enumList = new String[]{};
            this.nameToOwner = new Map<String, PlainObject>();
            PlainObject ownerObj = objVal;
            do {
                ownerObj.enumerateOwn(enumList, nameToOwner);
                ownerObj = ownerObj.proto;
            } while (ownerObj != null);
        }
        
        public override void onTryFinally() {
            System.assert(false, 'TRY_FINALLY instruction is not implemented by EnumPromise');
        }
        
        // ENUM_END -- the natural (non-abrupt) end of a for-in loop:
        public override void onNaturalCompletion(Context ctx) {
            // simply tear down this promise:
            Promise[] promises = ctx.vm.promises;
            promises.remove(promises.size() - 1);
        }
        
        public override Boolean handleAbruptCompletion(Context ctx, Instruc.AbruptCompletion event, Object val) {
            VirtualMachine vm = ctx.vm;
            // a throw event is always relevant to this promise; since a throw crosses right over function boundaries, it always tears down any 
            // for-in/enum promise that receives it and then continues to propagate the event up the promises stack:
            if (event.sid == Instruc.SID_THROW 
                    // a return is only relevant when this with stmt's host frame is active:
                    || event.sid == Instruc.SID_RETURN && hostFrame === vm.active) {
                // tear down this promise:
                Promise[] promises = vm.promises;
                Integer promisesLeft = promises.size() - 1;
                promises.remove(promisesLeft);
                // route the event to the next promise, if available:
                if (promisesLeft > 0)
                    return promises[promisesLeft - 1].handleAbruptCompletion(ctx, event, val);
                // else, fallthrough to return true...
                
            // break/continue is only relevant if the host frame is active and the target label is on a statement that encloses this promise's for-in
            // stmt (without crossing function boundaries):
            } else if ((event.sid == Instruc.SID_BREAK || event.sid == Instruc.SID_CONTINUE) && hostFrame === vm.active) {
                Set<String> enclosingLabels;
                if (event.sid == Instruc.SID_BREAK)
                    enclosingLabels = enumStart.enclosingBreakLabels;
                // else, it must be a continue event:
                else
                    enclosingLabels = enumStart.enclosingContLabels;
                
                if (enclosingLabels.contains(event.strVal)) {
                    // tear down this promise:
                    Promise[] promises = vm.promises;
                    Integer promisesLeft = promises.size() - 1;
                    promises.remove(promisesLeft);
                    // route the event to the next promise, if available:
                    if (promisesLeft > 0)
                        return promises[promisesLeft - 1].handleAbruptCompletion(ctx, event, val);
                    // else, fallthrough to return true...
                }
                // else, fallthrough to return true...
                // example: for(var foo in bar) { bad: while(true) { break bad; } } -- in this case, when BREAK is executed, the target "bad" label
                // doesn't enclose the active enum promise, and so the enum promise defers to the vm's default handling of BREAK (i.e. a jump)
            }
            // if the event was not relevant to this promise, OR we purposely fell through to here, then we allow the vm to perform its default
            // handling (i.e. a no-op in the case of a for-in loop end):
            return true;
            return null;
        }
    }
    */
}