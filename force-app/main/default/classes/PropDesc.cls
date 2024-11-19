global class PropDesc {
    // specific class where this property resides:
    public DataDesc host;
    // class where this property was originally defined (inherited from, if this.host !== this.inheritedHost):
    public DataDesc inheritedHost;
    // index in ptable; must be consistent for all subclasses that inherit this prop:
    public Integer pindex;
    public DataDesc typeDesc;
    // identifier must match IdentifierNamePatt = /[$_a-zA-Z][$_a-zA-Z0-9]*+/
    public String identifier;
    public Boolean writable;
    // The default value automatically assigned to this property for all newly minted instances of the host class:
    public Value initVal;
    // Properties are accessors if they define an Accessor implementation; in that case the property still holds a value 
    // internally, but this value is only made available to the get/set methods of the Accessor implementation, via a context 
    // object. 
    // !! Subclasses cannot define or override the accessor of an inherited property.
    public Accessor access;
}