global virtual class GetContext {
    //Environment env
    global PropDesc prop;
    global Value thisBinding;
    // Before Accessor.get is called, runtime logic sets val to the property's current internal value; after Accessor.get is 
    // called, runtime logic performs automatic type checking/conversion on the return value if Accessor.typeChecking == true
    global Value val;
}