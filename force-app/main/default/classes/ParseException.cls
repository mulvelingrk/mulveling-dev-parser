/*
 * Mike Ulveling
 */
global class ParseException extends Exception {
    public String msg;   
    public Lexer2.Token contextualStartLoc;
    public Lexer2.Token loc;
    
    public ParseException(String msg, Lexer2.Token contextualStartLoc, Lexer2.Token errorLoc) {
        this.msg = msg;
        this.contextualStartLoc = contextualStartLoc;
        this.loc = errorLoc;
    }
    
    public ParseException(String msg, Lexer2.Token errorLoc) {
        this.msg = msg;
        this.loc = errorLoc;
    }
    
    public override String getMessage() {
        return msg + ' \nAt: line ' + (loc == null ? '<unknown location>' : (loc.line + 1) + ', col ' + (loc.col + 1) + ', module ' + loc.moduleURI);
    }
}