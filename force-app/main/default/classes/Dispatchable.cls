global class Dispatchable {
	Integer vindex;
    DataDesc[] argvConversions;

    public Dispatchable(Integer vindex, DataDesc[] argvConversions) {
        this.vindex = vindex;
        this.argvConversions = argvConversions;
    }

    public FunctionDesc bind(DataDesc bindToClass) {
//        return bindToClass.vtable[this.vindex];
		System.assert(false, 'TOOD: implement');
		return null;
    }

    // argv must not be null, and argv size MUST match this.argvConversions size:
    public Value dispatch(Value thisBinding, Value[] argv) {
    	// TODO: no more argument conversions, except for subvstitution of NullObject values...

    	/*
        // Convert argument values that are imperfectly compatible with the declared formal argument type.
        // NOTE: argv is cloned if/when conversions occur, so as not to impart side-effects on calling code.
        Value[] mutatedArgv
        for (Integer i=0; i < argv.size(); i++)
            if (argvConversions[i] != null)
                if (mutatedArgv == null)
                    argv = mutatedArgv = argv.clone()
                argv[i] = argvConversions[i].valueOf(argv[i])

        FunctionDesc bindFunc = thisBinding.typeDesc.vtable[this.vindex]
        InvocationContext context = new InvocationContext(thisBinding, bindFunc, argv)
        return bindFunc.invokable.invoke(context)
        */

        System.assert(false, 'TODO: implement');
        return null;
    }
}