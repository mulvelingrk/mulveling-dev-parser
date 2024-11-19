global class FormalArg {
	    // The data type of this argument slot:
    public DataDesc typeDesc;
    // Quantifier arg slots: setting non-null values into quantLower and/or quantUpper facilitates support for the following 
    // quantifiers:
    //    ? => [0, 1]
    //    * => [0, null] 
    //    + => [1, null]
    //    {N} => [N, N]
    //    {N,} => [N, null]
    //    {N,M} => [N, M]
    // Only the last arg slot in a function signature can be configured as a quantifier slot.
    public Integer quantLower;
    public Integer quantUpper;
    // TODO: defaultVal will not be implemented for now...
    // defaultVal should only be available for use with a "?" quantifier
    public Value defaultVal;

    // Strict equality check for a given argument slot against this one. Used to match new function definitions against 
    // existing ones of the same signature, for the purpose of subclass overrides.
    public Boolean equals(FormalArg that) {
        return this.typeDesc === that.typeDesc && this.quantLower == that.quantLower && this.quantUpper == that.quantUpper;
    }
}