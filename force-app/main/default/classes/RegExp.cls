/*
 * Mike Ulveling
 */
global class RegExp extends PlainObject {
    global Pattern patt;
    global Boolean globalFlag;
    
    global RegExp(Context ctx, Pattern patt, Boolean globalFlag) {
        super(ctx, 'RegExp');
        this.patt = patt;
        this.globalFlag = globalFlag;
        
        // TODO: set proto
    }
}