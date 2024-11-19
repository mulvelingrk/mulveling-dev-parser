/*
 * Mike Ulveling
 * 
 * ECMAScript 8.7: The Reference Specification Type
 */
global class Reference {
    // the location of the referenced name in source code:
    public Lexer2.Token loc;
    
    // the holder object; must be an instance of either PlainObject, Environment, String, Double, Boolean, or null (i.e. undefined):
    public Object base;
    // the reference name against the base:
    public String name;
    
    // is this a strict mode reference:
    public Boolean strict;
    
    global Reference(Lexer2.Token loc, Object base, String name, Boolean strict) {
        this.loc = loc;
        this.base = base;
        this.name = name;
        this.strict = strict;
    }
}