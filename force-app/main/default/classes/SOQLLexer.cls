/*
* Mike Ulveling
*
* Don't touch this code if you're not me.
*
* Lexical analyzer for SOQL WHERE conditions. Highly performant, as far as lexical analysis in Apex goes. The token definitions here have purposefully
* been kept as simple and minimal as possible (e.g. no DATE, DATETIME, or QUALIFIED_NAME token types; DECIMAL_NUMBER tokens do not have signs); from
* here it's up to the parser to interpret and combine the basic elements into more complex entities.
*/
public class SOQLLexer {
    // This table is used by the parser to determine whether a next token instigates a RAISE, EXTEND, or MERGE action:
    public static final Integer[] ExprLevelTable = new Integer[]{};
    public static Integer tokid = 0;
    
    static Integer tokid(Integer exprRoutingLvl) {
        ExprLevelTable.add(exprRoutingLvl);
        return tokid++;
    }
    
    // empty token to serve as the "none" prior token before we've scanned our first token:
    public static final Integer EMPTY = tokid(-1);
    // the terminating "end-of-file" token:
    public static final Integer EOF = tokid(-1);
    // the terminating "error" token (i.e. token manifestation of a ScanException):
    public static final Integer ERROR = tokid(-1);
    
    // lexer/scanner error types:
    public static final Integer ERR_ILLEGAL_CHAR    = 0;
    public static final Integer ERR_UNTERM_STRING   = 1;
    public static final Integer ERR_ILLEGAL_TOK     = 2;
    public static final Integer ERR_STR_UNICODE_SEQ = 3;
    public static final Integer ERR_STR_HEX_SEQ     = 4;
    public static final Integer ERR_BROKEN_STRING   = 5;
    
    // creates a new token to the given specifications, and advances this cursor's index/line/col according to that token's metrics;
    // also automatically converts qualifying identifiers into keywords
    // !! processed lexeme may not be null; if lineCount is non-null and > 0 then nextCol cannot be null
    static Token newToken(Token cursor, Integer ttype, String processedLexeme, String rawLexeme, Integer lineCount, Integer nextCol) {
        rawLexeme = rawLexeme == null ? processedLexeme : rawLexeme;
        cursor.ttype = ttype;
        Token tok = cursor.clone();
        tok.lexeme = processedLexeme;
        cursor.index += rawLexeme.length();
        cursor.line += lineCount != null && lineCount > 0 ? lineCount : 0;
        cursor.col = lineCount != null && lineCount > 0 ? nextCol : cursor.col + rawLexeme.length();
        return tok;
    }
    
    static Token errorToken(Token cursor, String lexeme, Integer errorType, String msg, Token penTok) {
        Token err = cursor.clone();
        err.ttype = ERROR;
        err.lexeme = lexeme;
        err.errorType = errorType;
        err.errorMsg = msg;
        err.penTok = penTok;
        // don't increment cursor, since we're done lexing once we hit ERROR or EOF...
        return err;
    }
    
    static Token eofToken(Token cursor, Token penTok) {
        Token err = cursor.clone();
        err.ttype = EOF;
        err.lexeme = '<EOF>';
        err.penTok = penTok;
        // don't increment cursor, since we're done lexing once we hit ERROR or EOF...
        return err;
    }
    
    public class Token {
        public Integer ttype;
        // lexeme must not be left null. note that lexemes for string literals will have stripped quote chars and interpreted escape sequences:
        public String lexeme;
        public Integer leadLineBreaks;
        // true if there was and whitespace preceding this token:
        public Boolean hasLeadBoundary;
        public Integer index;
        public Integer line;
        public Integer col;
        public Boolean injected = false;
        
        // the following only applies to ttype == STRING_LITERAL:
        public String[] stringLitParts;
        public Integer[] stringLitCodes;
        
        // the following only applies to ttype == ERROR:
        public Integer errorType;
        public String errorMsg;
        
        // the following only applies to ttype == ERROR or EOF:
        // the token immediately preceding the ERROR:
        public Token penTok;
    }
    
    // spits out a token in a format useful for debugging lex'd token streams:
    public static String toString(Token tok) {
        if (tok.ttype >= KEYWORD_MINIMUM) {
            return tok.lexeme.toUpperCase();
        } else if (tok.ttype == NAME) {
            return 'NAME[' + tok.lexeme + ']';
        } else if (tok.ttype == DECIMAL_NUMBER) {
            return 'NUMBER[' + tok.lexeme + ']';
        } else if (tok.ttype == STRING_LITERAL) {
            return 'STRING[' + tok.lexeme + ']';
        } else {
            return tok.lexeme;
        }
    }
    
    // 1-char punctuators; no expression-lvl raising on any of these:
    public static final Integer COMMA         = tokid(-1);
    public static final Integer COLON         = tokid(-1);
    public static final Integer DOT           = tokid(-1);
    public static final Integer OPEN_PAREN    = tokid(-1);
    public static final Integer CLOSE_PAREN   = tokid(-1);
    public static final Integer OPEN_BRACKET  = tokid(-1);
    public static final Integer CLOSE_BRACKET = tokid(-1);
    public static final Integer QUEST_MARK    = tokid(-1);
    public static final Integer STAR          = tokid(-1);
    
    // The following operators NO LONGER raise a RefExpr to MathExpr
    public static final Integer PLUS  = tokid(-1); //tokid(4);
    public static final Integer MINUS = tokid(-1); //tokid(4);
    
    // The following operators raise a RefExpr (lvl 4) to a SimpleExpr (lvl 3):
    public static final Integer EQUALS              = tokid(3);
    public static final Integer NOT_EQUALS          = tokid(3);
    public static final Integer GREATER_THAN        = tokid(3);
    public static final Integer GREATER_THAN_EQUALS = tokid(3);
    public static final Integer LESS_THAN           = tokid(3);
    public static final Integer LESS_THAN_EQUALS    = tokid(3);
    
    public static final Integer LOGICAL_OR          = tokid(0);
    public static final Integer LOGICAL_AND         = tokid(1);
    public static final Integer LOGICAL_NOT         = tokid(-1);
    
    // complex tokens (i.e. lexeme is distinct from token type):
    public static final Integer NAME           = tokid(-1);
    public static final Integer DECIMAL_NUMBER = tokid(-1);
    public static final Integer STRING_LITERAL = tokid(-1);
    
    // keywords:
    public static final Integer KEYWORD_MINIMUM = tokid; // all keywords are >= this id
    public static final Integer KW_LIKE         = tokid(3); //tokid(-1);
    public static final Integer KW_OR           = tokid(0);
    public static final Integer KW_AND          = tokid(1);
    public static final Integer KW_NOT          = tokid(-1);
    public static final Integer KW_IN           = tokid(3); //tokid(-1);
    public static final Integer KW_INCLUDES     = tokid(3); //tokid(-1);
    public static final Integer KW_EXCLUDES     = tokid(3); //tokid(-1);
    public static final Integer KW_BEGINS_WITH  = tokid(3);
    public static final Integer KW_STARTS_WITH  = tokid(3);
    public static final Integer KW_ENDS_WITH    = tokid(3);
    public static final Integer KW_CONTAINS     = tokid(3);
    public static final Integer KW_BETWEEN      = tokid(3);
    // the following keywords are not expression-level:
    public static final Integer KW_SELECT       = tokid(-1);
    public static final Integer KW_FROM         = tokid(-1);
    public static final Integer KW_WHERE        = tokid(-1);
    public static final Integer KW_ORDER        = tokid(-1);
    public static final Integer KW_LIMIT        = tokid(-1);
    public static final Integer KW_ASC          = tokid(-1);
    public static final Integer KW_DESC         = tokid(-1);
    public static final Integer KW_NULLS        = tokid(-1);
    public static final Integer KW_LAST         = tokid(-1);
    public static final Integer KW_FIRST        = tokid(-1);
    public static final Integer KW_SAFE         = tokid(-1);
    public static final Integer KW_SYSTEM       = tokid(-1);
    public static final Integer KW_FIELDSET     = tokid(-1);
    // value keywords:
    public static final Integer VALUE_KEYWORD_MINIMUM = tokid;
    public static final Integer KW_TRUE         = tokid(-1);
    public static final Integer KW_FALSE        = tokid(-1);
    public static final Integer KW_NULL         = tokid(-1);
    // date formula value keywords:
    public static final Integer DATE_FORMULA_KEYWORD_MINIMUM = tokid;
    public static final Integer KW_TODAY               = tokid(-1);
    public static final Integer KW_YESTERDAY           = tokid(-1);
    public static final Integer KW_TOMORROW            = tokid(-1);
    public static final Integer KW_THIS_WEEK           = tokid(-1);
    public static final Integer KW_LAST_WEEK           = tokid(-1);
    public static final Integer KW_NEXT_WEEK           = tokid(-1);
    public static final Integer KW_THIS_MONTH          = tokid(-1);
    public static final Integer KW_LAST_MONTH          = tokid(-1);
    public static final Integer KW_NEXT_MONTH          = tokid(-1);
    public static final Integer KW_LAST_90_DAYS        = tokid(-1);
    public static final Integer KW_NEXT_90_DAYS        = tokid(-1);
    public static final Integer KW_THIS_QUARTER        = tokid(-1);
    public static final Integer KW_LAST_QUARTER        = tokid(-1);
    public static final Integer KW_NEXT_QUARTER        = tokid(-1);
    public static final Integer KW_THIS_YEAR           = tokid(-1);
    public static final Integer KW_LAST_YEAR           = tokid(-1);
    public static final Integer KW_NEXT_YEAR           = tokid(-1);
    public static final Integer KW_THIS_FISCAL_QUARTER = tokid(-1);
    public static final Integer KW_LAST_FISCAL_QUARTER = tokid(-1);
    public static final Integer KW_NEXT_FISCAL_QUARTER = tokid(-1);
    public static final Integer KW_THIS_FISCAL_YEAR    = tokid(-1);
    public static final Integer KW_LAST_FISCAL_YEAR    = tokid(-1);
    public static final Integer KW_NEXT_FISCAL_YEAR    = tokid(-1);
    // date formula value keywords with an "N" parameter:
    public static final Integer KW_DATE_FORMULA_N_KEYWORD_MINIMUM = tokid;
    public static final Integer KW_NEXT_N_DAYS            = tokid(-1);
    public static final Integer KW_LAST_N_DAYS            = tokid(-1);
    public static final Integer KW_NEXT_N_MONTHS          = tokid(-1);
    public static final Integer KW_LAST_N_MONTHS          = tokid(-1);
    public static final Integer KW_NEXT_N_QUARTERS        = tokid(-1);
    public static final Integer KW_LAST_N_QUARTERS        = tokid(-1);
    public static final Integer KW_NEXT_N_YEARS           = tokid(-1);
    public static final Integer KW_LAST_N_YEARS           = tokid(-1);
    public static final Integer KW_NEXT_N_FISCAL_QUARTERS = tokid(-1);
    public static final Integer KW_LAST_N_FISCAL_QUARTERS = tokid(-1);
    public static final Integer KW_NEXT_N_FISCAL_YEARS    = tokid(-1);
    public static final Integer KW_LAST_N_FISCAL_YEARS    = tokid(-1);
    public static final Integer KW_DATE_FORMULA_N_KEYWORD_MAXIMUM = tokid - 1;
    
    // transition states:
    
    // the "transition-state" bit is the 2^8 bit (256); the 7 bits below this can enumerate up to 255 different token types:
    static final Integer TS_BIT = 1 << 8;
    // use this mask with '&' to remove the lower token-type bits, thus revealing the transition-state:
    static final Integer TS_MASK = ~0 << 8;
    // use this mask with '&' to remove the upper transition-state bits, thus revealing the token-type (if any):
    static final Integer TOKEN_MASK = ~TS_MASK;
    
    static Integer tsid = 1;
    //// signals that we need to parse a complex token of the type specified in the lower bits (e.g. NAME):
    //static final Integer TS_COMPLEX = tsid++ << 8;
    // signals that we need to try a 2-char lookup, and if that fails we can fallback to the token-type specified
    // in the lower bits:
    static final Integer TS_NEXT = tsid++ << 8;
    static final Integer TS_NAME = tsid++ << 8;
    static final Integer TS_NUMBER = tsid++ << 8;
    //    static final Integer TS_NOT_EQUALS = tsid++ << 8;
    static final Integer TS_LOGICAL_OR = tsid++ << 8;
    static final Integer TS_LOGICAL_AND = tsid++ << 8;
    // we use special transition-states for strings, instead of (TS_COMPLEX | STRING_LITERAL), so that we can differentiate
    // between the SQ and DQ flavors:
    static final Integer TS_SQ_STRING = tsid++ << 8;
    static final Integer TS_DQ_STRING = tsid++ << 8;
    
    // using a hash map here would look more elegant, but the following scheme is far more performant (in Apex, indexOf is much faster than a Map
    // lookup, at least until the search string becomes extremely long
    // !! note that entries for letters and digits are generated and added in the following static block
    static String TransStateLookup1 = ',:()[]+-=!|&\'"><.?*';
    // resolves 1 char of lookahead to a concrete token type, a transition-state, or null (i.e. not a legal "black" token):
    static final Integer[] TransStateTable1 = new Integer[]{
        COMMA,
        COLON,
        OPEN_PAREN,
        CLOSE_PAREN,
        OPEN_BRACKET,
        CLOSE_BRACKET,
        PLUS,
        MINUS,
        EQUALS,
        //        TS_NOT_EQUALS,
        TS_NEXT | LOGICAL_NOT,
        TS_LOGICAL_OR,
        TS_LOGICAL_AND,
        TS_SQ_STRING,
        TS_DQ_STRING,
        TS_NEXT | GREATER_THAN,
        TS_NEXT | LESS_THAN,
        TS_NEXT | DOT,
        QUEST_MARK,
        STAR
    };
    // add transition-states for the usual ASCII digits [0-9] and letters [a-zA-Z]:
    static {
        for (Integer i=0; i <=9; i++) {
            TransStateLookup1 += i;
            //TransStateTable1.add(TS_COMPLEX | DECIMAL_NUMBER);
            TransStateTable1.add(TS_NUMBER);
        }
        String alpha = 'abcdefghijklmnopqrstuvwxyz';
        String ch;
        for (Integer i=0; i < alpha.length(); i++) {
            TransStateLookup1 += (ch = alpha.mid(i, 1));
            //TransStateTable1.add(TS_COMPLEX | NAME);
            TransStateTable1.add(TS_NAME);
            TransStateLookup1 += (ch = ch.toUpperCase());
            //TransStateTable1.add(TS_COMPLEX | NAME);
            TransStateTable1.add(TS_NAME);
        }
    }
    // concats all possible whitespace chars with TransStateLookup1, so that the boundary scanner loop can collect as much information as possible
    // in just 1 indexOf call plus 1 array-access:
    static final String WhiteBlackLookup = ' \t\n\r' + TransStateLookup1;
    
    // resolves 2 chars of lookahead to a concrete token type, or null -- i.e. fallback to the token type carried by the lower-bits of the prior
    //result from tsMap1:
    static String TransStateLookup2 = '!=>=<=<>';
    static final Integer[] TransStateTable2 = new Integer[]{
        NOT_EQUALS, null,
        GREATER_THAN_EQUALS, null,
        LESS_THAN_EQUALS, null,
        NOT_EQUALS, null
     };
    // add transition states for \.\d (e.g. '.9'):
    static {
        for (Integer i=0; i <=9; i++) {
            TransStateLookup2 += '.' + i;
            //TransStateTable2.add(TS_COMPLEX | DECIMAL_NUMBER);
            TransStateTable2.add(TS_NUMBER);
            TransStateTable2.add(null);
        }
    }
    
    static final Map<String, Integer> KeywordsMap = new Map<String, Integer>{
        'OR'       => KW_OR,
        'AND'      => KW_AND,
        'NOT'      => KW_NOT,
        'like'     => KW_LIKE,
        'IN'       => KW_IN,
        'INCLUDES' => KW_INCLUDES,
        'EXCLUDES' => KW_EXCLUDES,
        'beginsWith' => KW_BEGINS_WITH,
        'startsWith' => KW_STARTS_WITH,
        'endsWith'   => KW_ENDS_WITH,
        'contains'   => KW_CONTAINS,
        'between'    => KW_BETWEEN,
        'SELECT'   => KW_SELECT,
        'FROM'     => KW_FROM,
        'WHERE'    => KW_WHERE,
        'ORDER'    => KW_ORDER,
        'LIMIT'    => KW_LIMIT,
        'ASC'      => KW_ASC,
        'DESC'     => KW_DESC,
        'NULLS'    => KW_NULLS,
        'LAST'     => KW_LAST,
        'FIRST'    => KW_FIRST,
        'SAFE'     => KW_SAFE,
        'SYSTEM'   => KW_SYSTEM,
        'FIELDSET' => KW_FIELDSET,
        'true'  => KW_TRUE,
        'false' => KW_FALSE,
        'null'  => KW_NULL,
        'TODAY'                  => KW_TODAY,
        'YESTERDAY'              => KW_YESTERDAY,
        'TOMORROW'               => KW_TOMORROW,
        'THIS_WEEK'              => KW_THIS_WEEK,
        'LAST_WEEK'              => KW_LAST_WEEK,
        'NEXT_WEEK'              => KW_NEXT_WEEK,
        'THIS_MONTH'             => KW_THIS_MONTH,
        'LAST_MONTH'             => KW_LAST_MONTH,
        'NEXT_MONTH'             => KW_NEXT_MONTH,
        'LAST_90_DAYS'           => KW_LAST_90_DAYS,
        'NEXT_90_DAYS'           => KW_NEXT_90_DAYS,
        'THIS_QUARTER'           => KW_THIS_QUARTER,
        'LAST_QUARTER'           => KW_LAST_QUARTER,
        'NEXT_QUARTER'           => KW_NEXT_QUARTER,
        'THIS_YEAR'              => KW_THIS_YEAR,
        'LAST_YEAR'              => KW_LAST_YEAR,
        'NEXT_YEAR'              => KW_NEXT_YEAR,
        'THIS_FISCAL_QUARTER'    => KW_THIS_FISCAL_QUARTER,
        'LAST_FISCAL_QUARTER'    => KW_LAST_FISCAL_QUARTER,
        'NEXT_FISCAL_QUARTER'    => KW_NEXT_FISCAL_QUARTER,
        'THIS_FISCAL_YEAR'       => KW_THIS_FISCAL_YEAR,
        'LAST_FISCAL_YEAR'       => KW_LAST_FISCAL_YEAR,
        'NEXT_FISCAL_YEAR'       => KW_NEXT_FISCAL_YEAR,
        'NEXT_N_DAYS'            => KW_NEXT_N_DAYS,
        'LAST_N_DAYS'            => KW_LAST_N_DAYS,
        'NEXT_N_MONTHS'          => KW_NEXT_N_MONTHS,
        'LAST_N_MONTHS'          => KW_LAST_N_MONTHS,
        'NEXT_N_QUARTERS'        => KW_NEXT_N_QUARTERS,
        'LAST_N_QUARTERS'        => KW_LAST_N_QUARTERS,
        'NEXT_N_YEARS'           => KW_NEXT_N_YEARS,
        'LAST_N_YEARS'           => KW_LAST_N_YEARS,
        'NEXT_N_FISCAL_QUARTERS' => KW_NEXT_N_FISCAL_QUARTERS,
        'LAST_N_FISCAL_QUARTERS' => KW_LAST_N_FISCAL_QUARTERS,
        'NEXT_N_FISCAL_YEARS'    => KW_NEXT_N_FISCAL_YEARS,
        'LAST_N_FISCAL_YEARS'    => KW_LAST_N_FISCAL_YEARS
    };
                
    // !! note that the parser can identify strict-mode reserved tokens by the test: token.ttype >= STRICT_RESERVED_MINIMUM:
    static String KeywordsLookup = '';
    static Integer[] KeywordsTable;
    static Integer[] KeywordLenTable;
    static {
        String keywordsList =
            'OR AND NOT like IN INCLUDES EXCLUDES beginsWith startsWith endsWith contains between SELECT FROM WHERE ORDER LIMIT ASC DESC null NULLS LAST FIRST SAFE SYSTEM FIELDSET true false ' +
            'TODAY YESTERDAY TOMORROW THIS_WEEK LAST_WEEK NEXT_WEEK THIS_MONTH LAST_MONTH NEXT_MONTH LAST_90_DAYS NEXT_90_DAYS THIS_QUARTER LAST_QUARTER NEXT_QUARTER ' +
            'THIS_YEAR LAST_YEAR NEXT_YEAR THIS_FISCAL_QUARTER LAST_FISCAL_QUARTER NEXT_FISCAL_QUARTER THIS_FISCAL_YEAR LAST_FISCAL_YEAR NEXT_FISCAL_YEAR ' +
            'NEXT_N_DAYS LAST_N_DAYS NEXT_N_MONTHS LAST_N_MONTHS NEXT_N_QUARTERS LAST_N_QUARTERS NEXT_N_YEARS LAST_N_YEARS NEXT_N_FISCAL_QUARTERS LAST_N_FISCAL_QUARTERS NEXT_N_FISCAL_YEARS LAST_N_FISCAL_YEARS';
        String[] Keywords = keywordsList.split(' ');
        KeywordsTable = new Integer[keywordsList.replaceAll('[ ]', '').length()];
        KeywordLenTable = new Integer[KeywordsTable.size()];
        for (String keyword: Keywords) {
            KeywordsTable[KeywordsLookup.length()] = KeywordsMap.get(keyword);
            KeywordLenTable[KeywordsLookup.length()] = keyword.length();
            KeywordsLookup += keyword;
        }
    }
    
    static final String NullChar = String.fromCharArray(new Integer[]{ 0 });
    static final String NameChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_';
    static final String DecimalDigits = '0123456789.';
    static final String UnicodeSpecialLineTerminators = String.fromCharArray(new Integer[]{ 2028, 2029 });
    static final String NormalModeBreakingCharsSQ = '\'\n\r\\' + NullChar;
    // note how we include single-quote as a breaking char even for DQ strings; this is so we can flag it with code == 1 in the
    // compiled literal parts/codes:
    static final String NormalModeBreakingCharsDQ = '\'"\n\r\\' + NullChar;
    public static final String HexadecimalDigits = '0123456789abcdef';
    
    public String stream;
    String[] streamArray; // array of chars
    Integer streamLen;
    // !! cursor.ttype will hold the token-type of the prior token until the new token is verified and instantiated.
    Token cursor;
    
    // the starting token-stack size (i.e. lmt + 1) is 20; this will double as necessary:
    public Token[] toks = new Token[20];
    public Integer lmt = -1;
    Integer top = -1;
    public Integer next = 0;
    
    // scans all tokens from the source code into the tokens-stack, until we hit a terminating EOF, ERROR, or NEEDS_PARSER_FEEDBACK (to be determined) token:
    public void scanAll() {
        String[] streamArray = this.streamArray;
        Integer streamLen = this.streamLen;
        String stream = this.stream;
        Token cursor = this.cursor;
        try {
            // scanToken loop; breaks when we encounter the EOF token:
            do {
                if (top >= lmt) {
                    Integer lmtInc = Math.max(10, lmt + 1);
                    toks.addAll(new Token[lmtInc]);
                    lmt += lmtInc;
                } else {
                    // !! following is the body of the scanToken() method; we inline it here for efficiency:
                    String ch1;
                    Integer
                        index = cursor.index,
                        tsIndex1;
                    
                    cursor.leadLineBreaks = 0;
                    // the following while loop scans consecutive whitespace chars, i.e. a leading whitespace boundary:
                    Integer wbIndex;
                    Integer colStart = index;
                    // common whitespace chars occupy the first 3 positions of WhiteBlackLookup; after that is all the black-token start chars --
                    // thus, when we encounter a "black" char, we can get its 1st transition-state index by simply subtracting 3. we only get -1
                    // when we hit an invalid char (e.g. '?') or EOF:
                    while ((wbIndex = WhiteBlackLookup.indexOf(streamArray[index])) < 4 && wbIndex > -1) {
                        index++;
                        // if we got an \r char:
                        if (wbIndex == 3) {
                            cursor.leadLineBreaks++;
                            cursor.col = 0;
                            // If a \n follows a \r then it's a stupid Windows \r\n sequence and we should consume it.
                            // !! Remember index was already incremented to next pos (see above!) so we don't need to + 1 here!
                            if (streamArray[index] == '\n') {
                                index++;
                            }
                            colStart = index;
                        // else if we got a \n char:
                        } else if (wbIndex == 2) {
                            cursor.leadLineBreaks++;
                            cursor.col = 0;
                            colStart = index;
                        }
                    }
                    
                    // determine whether we scanned any boundary, and increment the cursor appropriately:
                    if (index > cursor.index) {
                        // update index and increment col and line:
                        cursor.index = index;
                        cursor.col += index - colStart;
                        //System.debug('Adding ' + cursor.leadLineBreaks + ' line breaks for token at index ' + index);
                        cursor.line += cursor.leadLineBreaks;
                        cursor.hasLeadBoundary = true;
                    } else {
                        cursor.hasLeadBoundary = false;
                    }
                    
                    // check to see if we're now at EOF after advancing past the boundary:
                    if (index < streamLen) {
                        // since we've determined we're not looking at EOF, a -1 indicates an illegal char:
                        if (wbIndex <= -1) {
                            //System.debug('White-Black lookup failed on char code ' + streamArray[index - 1].charAt(0) 
                            //    + ' :: ' + streamArray[index].charAt(0) + ' :: ' + streamArray[index + 1].charAt(0));
                            // TODO: allow for an option to treat illegal char as EOF, rather than throwing a ScanException?
                            // errorToken(Token cursor, String lexeme, Integer errorType, String msg, IntegerToken penTok)
                            throw new ScanException(errorToken(cursor, streamArray[index], ERR_ILLEGAL_CHAR,
                                'illegal character \'' + streamArray[index] + '\'', toks[top]));
                        }
                        // if we reach here then we're looking at the start of a black token; set the transition-state index and char we're
                        // currently looking at:
                        tsIndex1 = wbIndex - 4; // guaranteed to be >= 0 and < TransStateTable1.size()
                        ch1 = streamArray[index];
                    
                    // else we're looking at EOF:
                    } else {
                        //toks[++top] = termEOF(cursor);
                        Token penTok = top > -1 ? toks[top] : null;
                        toks[++top] = eofToken(cursor, penTok);
                        break; // break the outer scanToken loop
                    }
                    
                    Integer tsRes1 = TransStateTable1[tsIndex1];
                    // if we've unambiguously matched a simple 1-char operator token, then create and return it immediately:
                    if (tsRes1 < TS_BIT) {
                        // construct the new token inline, to save a call:
                        cursor.ttype = tsRes1;
                        Token tok = cursor.clone();
                        cursor.index += 1;
                        cursor.col += 1;
                        tok.lexeme = ch1;
                        toks[++top] = tok;
                        continue;
                    } else if (tsRes1 == TS_NAME) {
                        // we already know the 1st char is in the set [a-zA-Z], since we got we got a tsRes1 and these are the only
                        // identifier start-chars in tsIndex1. thus, we immediately advance past it the start char, then scan past
                        // every other "NAMECHAR" char ([a-zA-Z0-9_]) that we encounter:
                        Integer cur = index + 1;
                        // we don't use isAlphanumeric here because it also identifies extended unicode letters and digits:
                        while (NameChars.indexOf(streamArray[cur]) > -1) {
                            cur++;
                        }
                        
                        String lexeme = stream.substring(index, cur);
                        // for identifiers, we must attempt to resolve the lexeme to a keyword; if the lexeme is a keyword, then the
                        // following logic will set ttype to the appropriate KW_ type:
                        Integer lookupIndex = KeywordsLookup.indexOfIgnoreCase(lexeme);
                        if (lookupIndex < 0) {
                            cursor.ttype = NAME;
                        } else {
                            cursor.ttype = KeywordsTable[lookupIndex];
                            if (cursor.ttype == null || KeywordLenTable[lookupIndex] != cur - index) {
                                cursor.ttype = NAME;
                            }
                        }
                        Token tok = cursor.clone();
                        cursor.index = cur;
                        cursor.col += cur - index;
                        tok.lexeme = lexeme;
                        toks[++top] = tok;
                        continue;
                    } else if (tsRes1 == TS_NUMBER) {
                        // !! note that the following scanner logic in inlined for performance, but we could call scanDecimalNum for cleaner
                        // code.
                        // !! here, we know that ch1 is a digit [1-9]
                        Integer cur = index + 1; // we already know ch1 is a digit [1-9]
                        Integer digitType;
                        // states:
                        // 0 => start state; valid integer part
                        // 1 => decimal part; valid
                        Integer state = 0;
                        // scan [0-9] and '.' chars:
                        while ((digitType = DecimalDigits.indexOf(streamArray[cur])) > -1) {
                            // we got a '.' char:
                            if (digitType == 10) {
                                // only state 0 accepts a decimal:
                                if (state != 0)
                                    break;
                                // state 0 proceeds to state 1 when it gets a decimal:
                                else
                                    state = 1;
                            }
                            cur++;
                        }
                        // inline token construction:
                        cursor.ttype = DECIMAL_NUMBER;
                        Token tok = cursor.clone();
                        tok.lexeme = stream.substring(index, cur);
                        cursor.index = cur;
                        cursor.col += cur - index;
                        toks[++top] = tok;
                        continue;
                    } else if (tsRes1 == TS_SQ_STRING || tsRes1 == TS_DQ_STRING) {
                        // advance past the leading quote-char:
                        Integer cur = index + 1;
                        String terminatingChars = tsRes1 == TS_SQ_STRING ? NormalModeBreakingCharsSQ : NormalModeBreakingCharsDQ;
                        do {
                            // scan chars until we encounter a terminating quote (of matching flavor) or a line-terminator:
                            while (!terminatingChars.contains(streamArray[cur])) {
                                cur++;
                            }
                            // detect a null-char marking end-of-input:
                            if (cur == streamLen) {
                                // errorToken(Token cursor, String lexeme, Integer errorType, String msg, IntegerToken penTok)
                                throw new ScanException(errorToken(cursor, stream.substring(index, cur), ERR_UNTERM_STRING,
                                                                   'unterminated string constant', toks[top]));
                            } else if (streamArray[cur] == NullChar) {
                                // else if we have a real null-char in the string literal, then carry on:
                                continue;
                            } else {
                                // else we have a end-quote, line-break, or backslash which must end our simple scan:
                                break;
                            }
                        } while (true);
                        
                        // if we're looking at the same quote-char that started the string, then we've successfully scanned a simple string:
                        if (streamArray[cur].equals(ch1)) {
                            // inline token construction:
                            cursor.ttype = STRING_LITERAL;
                            Token tok = cursor.clone();
                            tok.lexeme = stream.substring(index, cur + 1);
                            // strips the enclosing quotes:
                            tok.stringLitParts = new String[]{ stream.substring(index + 1, cur) };
                                tok.stringLitCodes = new Integer[]{ 0 };
                                    cursor.index += tok.lexeme.length();
                            cursor.col += tok.lexeme.length();
                            toks[++top] = tok;
                            continue;
                        
                        // else, we have either a complex string or an invalid string; use the more rigorous (but slower) scanner:
                        } else {
                            toks[++top] = scanStringLit(this, index, cur, tsRes1 == TS_DQ_STRING);
                            continue;
                        }
                        
                    // else, we got either TS_NEXT, TS_LOGICAL_OR, or TS_LOGICAL_NOT - therefore we must inspect 2 lookahead chars to determine
                    // the next action:
                    } else {
                        Integer ts1, tsIndex2, tsRes2;
                        String ch2 = stream.mid(index, 2);
                        if ((ts1 = tsRes1 & TS_MASK) == TS_NEXT) {
                            // !! note that the tsRes2 != null condition prevents matches on mixed 2-char tokens, e.g. '+-':
                            if (index + 1 < streamLen && (tsIndex2 = TransStateLookup2.indexOf(ch2)) > -1 && (tsRes2 = TransStateTable2[tsIndex2]) != null) {
                                // note that DECIMAL_NUMBER is the only complex token that can be returned by tsMap2:
                                // if we unambiguously matched a 2-char operator token, then return it:
                                if (tsRes2 < TS_BIT) {
                                    // create the new token inline, to save a call:
                                    cursor.ttype = tsRes2;
                                    Token tok = cursor.clone();
                                    tok.lexeme = ch2;
                                    cursor.index += 2;
                                    cursor.col += 2;
                                    toks[++top] = tok;
                                    continue;
                                    
                                // DECIMAL_NUMBER will have a special transition-state that indicates a start-state for the decimal scanner:
                                } else if (tsRes2 == TS_NUMBER) {
                                    // we must have a \.[0-9] (i.e. starting-state 1) number:
                                    toks[++top] = scanDecimalNum(this, 1, index, index + 2);
                                    continue;
                                }

                            // else if no 2-char lookahead token-type match, then we fallback to the 1-char simple token type. note that for this lexcial
                            // language the only possibility here is a fallback DOT token:
                            } else {
                                // create the new token inline, to save a call:
                                cursor.ttype = tsRes1 & TOKEN_MASK;
                                Token tok = cursor.clone();
                                tok.lexeme = ch1;
                                cursor.index += 1;
                                cursor.col += 1;
                                toks[++top] = tok;
                                continue;
                            }
                        /*
                        } else if (ts1 == TS_NOT_EQUALS) {
                            if (ch2 != '!=') {
                                // a bang char followed by <eof> or any alphanumeric char should be reported as an illegal bang char:
                                if (index + 1 >= streamLen || ch2.mid(1, 1).isAlphanumeric()) {
                                    throw new ScanException(errorToken(cursor, '!', ERR_ILLEGAL_CHAR,
                                    'illegal character \'!\'', toks[top]));
                                // a bang char followed by a symbol should be reported as an illegal 2-char token:
                                } else {
                                    throw new ScanException(errorToken(cursor, ch2, ERR_ILLEGAL_TOK,
                                    'illegal token \'' + ch2 + '\'', toks[top]));
                                }
                            }
                        toks[++top] = newToken(cursor, NOT_EQUALS, ch2, null, null, null);
                        continue;
                        */
                        } else if (ts1 == TS_LOGICAL_OR || ts1 == TS_LOGICAL_AND) {
                            if (ch2 == '||') {
                                toks[++top] = newToken(cursor, LOGICAL_OR, ch2, null, null, null);
                            } else if (ch2 == '&&') {
                                toks[++top] = newToken(cursor, LOGICAL_AND, ch2, null, null, null);
                            } else {
                                // a { &, | } char followed by <eof> or any alphanumeric char should be reported as an illegal char:
                                if (index + 1 >= streamLen || ch2.mid(1, 1).isAlphanumeric() || !ch2.mid(1, 1).isAsciiPrintable() 
                                        || ch2.mid(1, 1).isWhitespace()) {
                                    throw new ScanException(errorToken(cursor, '!', ERR_ILLEGAL_CHAR,
                                        'illegal character \'' + ch2.mid(0, 1) + '\'', toks[top]));
                                // a { &, | } char followed by a symbol should be reported as an illegal 2-char token:
                                } else {
                                    throw new ScanException(errorToken(cursor, ch2, ERR_ILLEGAL_TOK,
                                        'illegal token \'' + ch2 + '\'', toks[top]));
                                }
                            }
                            continue;
                        // else, invalid 2-char sequence that was not TS_NEXT, TS_LOGICAL_OR, or TS_LOGICAL_AND
                        // TODO: is this branch even reachable? I don't think so (because it would have hit illegal-char at the 1st
                        // char's white-black lookup), but if it is, document how it can be reached:
                        } else {
                            // check for <eof> as the 2nd char:
                            if (index + 1 >= streamLen) {
                                throw new ScanException(errorToken(cursor, ch2.mid(0, 1), ERR_ILLEGAL_CHAR,
                                    'illegal character \'' + ch2.mid(0, 1) + '\'', toks[top]));
                            } else {
                                throw new ScanException(errorToken(cursor, ch2, ERR_ILLEGAL_TOK,
                                    'illegal token \'' + ch2 + '\'', toks[top]));
                            }
                        }
                    }
                    
                } // if (top >= lmt)
                
            } while (true); // outer scanToken loop
        } catch (ScanException e) {
            /*
            // !! note that cursor has already been incremented by the lead boundary (if any), but not by the failed/illegal token. this means that
            // the lead token's lexeme/data will be "lost" after this failure, but this should not be an issue since there is no potential/need
            // for error recovery (i.e. no continued scanning) after any of the ScanExceptions:
            Token errorLoc = cursor.clone();
            errorLoc.index += e.offendingOffsetChars;
            if (e.offendingOffsetLines > 0) {
                errorLoc.line += e.offendingOffsetLines;
                errorLoc.col = e.offendingOffsetCol;
            } else {
                errorLoc.col += e.offendingOffsetChars;
            }
            errorLoc.lexeme = e.offendingLexeme;
            */
            
            toks[++top] = e.errorTok;
            
            // TODO: push an ERROR token rather than throwing a ParseException (should we also push EOF after ERROR?)...
            //SOQLParser.parseErr(errorLoc, e.msg);
        } finally {
            // clear out some of the input text to save heap space:
            // !! keep stream around to validate Directive Prologues and to provide the literal source code for functions:
            //stream = null;
            streamArray = null;
        }
    } // scanAll()
    
    public override String toString() {
        String[] parts = new String[]{};
        for (Token t : toks) {
            parts.add(toString(t));
            if (t.ttype == EOF) {
                break;
            }
        }
        return String.join(parts, ' ');
    }
    
    // takes the starting state as a parameter, since in some cases we wish to start scanning after a decimal:
    static Token scanDecimalNum(SOQLLexer lex, Integer state, Integer index, Integer cur) {
        String[] streamArray = lex.streamArray;
        Integer digitType;
        // states:
        // 0 => start state; valid integer part
        // 1 => decimal part; valid
        // scan [\.0-9] chars:
        // scan [0-9] and '.' chars:
        while ((digitType = DecimalDigits.indexOf(streamArray[cur])) > -1) {
            // we got a '.' char:
            if (digitType == 10) {
                // only state 0 accepts a decimal:
                if (state != 0)
                    break;
                // state 0 proceeds to state 1 when it gets a decimal:
                else
                    state = 1;
            }
            cur++;
        }
        Token cursor = lex.cursor;
        cursor.ttype = DECIMAL_NUMBER;
        Token tok = cursor.clone();
        cursor.index = cur;
        cursor.col += cur - index;
        tok.lexeme = lex.stream.substring(index, cur);
        return tok;
    }
    
    // in a string literal token, a backslash followed by any of the following chars requires special processing:
    static final String StringEscapeTypesLookup = 'xu\n\r0bft%_\'\\nr';
    // escape codes corresponding to the above chars:
    // null => ignore this escape sequence (i.e. line continuations)
    // 0 => corresponding part is resolved string of chars (no further escape processing needed on the part)
    // 1 => part is a backslashed char (escape is mandatory in SOQL string): single-quote, backslash, newline, carriage return
    // 2 => part is a backslashed char, with meaning determined by whether it's the target of a LIKE op: '%', '_'
    static final Integer[] StringEscapeTypeCodeTable = new Integer[]{ 0, 0, null, null, 0, 0, 0, 0, 2, 2, 1, 1, 1, 1 };
    static final String[] StringEscapeTypePartTable = new String[]{ null, null, null, null, String.fromCharArray(new Integer[]{ 0 }), '\b', '\f', '\t', '%', '_', '\'', '\\', 'n', 'r' };
            
    // rigorously scans string literals:
    static Token scanStringLit(SOQLLexer lex, Integer index, Integer cur, Boolean isDQ) {
        String[] streamArray = lex.streamArray;
        Integer state = 0;
        String normalModeBreakingChars = isDQ ? NormalModeBreakingCharsDQ : NormalModeBreakingCharsSQ;
        
        // states:
        // 0 => normal mode; we are not currently inside an escape sequence
        // 1 => in a unicode esc-sequence; has 0 digits; invalid until we get 4
        // 2 => in a unicode esc-sequence; has 1 digit; invalid until we get 4
        // 3 => in a unicode esc-sequence; has 2 digits; invalid until we get 4
        // 4 => in a unicode esc-sequence; has 3 digits; invalid until we get 4
        // 5 => in a hex esc-sequence; has 0 digits; invalid until we get 2
        // 6 => in a hex esc-sequence; has 0 digits; invalid until we get 2
        String[] parts = new String[]{}; // processed parts; to be joined on final token creation
        Integer[] codes = new Integer[]{};
        Integer lastPartEnd = index + 1; // remember to advance past the starting quote char
        Integer hexValue;
        String ch;
        // if non-null, this stores the value of cur at the time the last line-continuation escape sequence was encountered (points past those line-
        // break chars):
        Integer lastContinuationCur;
        Integer lineContinuationCount = 0;
        do {
            if (state == 0) {
                if (!normalModeBreakingChars.contains(ch = streamArray[cur])) {
                    cur++;
                } else if ('\\'.equals(ch)) {
                    // check for a special escape sequence that requires additional processing:
                    Integer escType = StringEscapeTypesLookup.indexOf(streamArray[cur + 1]);
                    
                    if (cur > lastPartEnd) {
                        parts.add(lex.stream.substring(lastPartEnd, cur));
                        codes.add(0);
                    }
                    if (escType > 3) {
                        parts.add(StringEscapeTypePartTable[escType]);
                        codes.add(StringEscapeTypeCodeTable[escType]);
                        lastPartEnd = cur = cur + 2;
                    // else if it's non-SOQL-escape, e.g. "\m", we will discard the backslash and keep the subsequent char:
                    } else if (escType < 0) {
                        cur++; // advance past the "\"
                        if (cur == lex.streamLen) {
                            throw new ScanException(errorToken(lex.cursor, lex.stream.substring(index, cur), ERR_UNTERM_STRING,
                                'unterminated string constant', lex.toks[lex.top]));
                        }
                        // add the subsequent char as a literal part:
                        parts.add(streamArray[cur]);
                        codes.add(0);
                        // advance past the plain-char and continue in normal mode:
                        lastPartEnd = cur = cur + 1;
                    // else if it's a line-continuation:
                    } else if (escType > 1) {
                        // check for a stupid M$-Windows \r\n line-break sequence:
                        if (escType == 3 && '\n'.equals(streamArray[cur + 2])) {
                            cur += 3;
                        } else {
                            cur += 2;
                        }
                        lineContinuationCount++;
                        lastContinuationCur = lastPartEnd = cur;
                    // unicode escape sequence:
                    } else if (escType == 1) {
                        state = 1;
                        cur += 2;
                    // hex escape sequence:
                    } else if (escType == 0) {
                        state = 5;
                        cur += 2;
                    }
                    
                } else if (ch == NullChar) {
                    if (cur == lex.streamLen) {
                        throw new ScanException(errorToken(lex.cursor, lex.stream.substring(index, cur), ERR_UNTERM_STRING,
                            'unterminated string constant', lex.toks[lex.top]));
                    } else {
                        cur++;
                        continue;
                    }
                    
                // else this must be either a line-break (illegal) or a terminating quote char (must match the start quote) or a non-terminating quote
                // char which needs us to add in the backslash escape (i.e. unescaped single quote inside a DQ string). the former cases will be checked
                // and verified after we break out of this scanning loop; the latter case can be handled here before the state=0 loop is continued:
                } else {
                    if (isDQ && ch == '\'') {
                        if (cur > lastPartEnd) {
                            parts.add(lex.stream.substring(lastPartEnd, cur));
                            codes.add(0);
                        }
                        parts.add('\'');
                        codes.add(1);
                        lastPartEnd = cur = cur + 1;
                        continue;
                    }
                    break;
                }
                
            // else, we are in a unicode escape sequence:
            } else if (state < 5) {
                if (cur == lex.streamLen) {
                    throw new ScanException(errorToken(lex.cursor, lex.stream.substring(index, cur), ERR_UNTERM_STRING,
                        'unterminated string constant', lex.toks[lex.top]));
                }
                Integer digitVal = HexadecimalDigits.indexOfIgnoreCase(streamArray[cur]);
                if (digitVal > -1) {
                    if (state == 1) {
                        state = 2;
                        hexValue = digitVal << 12;
                    } else if (state == 2) {
                        state = 3;
                        hexValue += digitVal << 8;
                    } else if (state == 3) {
                        state = 4;
                        hexValue += digitVal << 4;
                    } else {
                        state = 0;
                        hexValue += digitVal;
                        parts.add(String.fromCharArray(new Integer[] { hexValue }));
                        codes.add(0);
                        lastPartEnd = ++cur;
                        continue;
                    }
                    cur++;
                } else {
                    Integer seqStart = cur - state - 1;
                    throw new ScanException(errorToken(
                        strErrCursor(lex.cursor, lineContinuationCount, lastContinuationCur, seqStart),
                        lex.stream.substring(seqStart, cur + 1), ERR_STR_UNICODE_SEQ,
                        'invalid unicode escape sequence in string constant', lex.toks[lex.top]));
                }
                
            // else, we must be in a hex escape sequence:
            } else {
                if (cur == lex.streamLen) {
                    throw new ScanException(errorToken(lex.cursor, lex.stream.substring(index, cur), ERR_UNTERM_STRING,
                        'unterminated string constant', lex.toks[lex.top]));
                }
                Integer digitVal = HexadecimalDigits.indexOfIgnoreCase(streamArray[cur]);
                if (digitVal > -1) {
                    if (state == 5) {
                        state = 6;
                        hexValue = digitVal << 4;
                    } else {
                        state = 0;
                        hexValue += digitVal;
                        parts.add(String.fromCharArray(new Integer[] { hexValue }));
                        codes.add(0);
                        lastPartEnd = ++cur;
                        continue;
                    }
                    cur++;
                } else {
                    Integer seqStart = cur - state + 3;
                    throw new ScanException(errorToken(
                        strErrCursor(lex.cursor, lineContinuationCount, lastContinuationCur, seqStart), 
                        lex.stream.substring(seqStart, cur + 1), ERR_STR_HEX_SEQ,
                        'invalid hex escape sequence in string constant', lex.toks[lex.top]));
                }
            }
        } while (true);
        
        if (state > 0) {
            if (state < 5) {
                Integer seqStart = cur - state - 2;
                throw new ScanException(errorToken(
                    strErrCursor(lex.cursor, lineContinuationCount, lastContinuationCur, seqStart),
                    lex.stream.substring(seqStart, cur), ERR_STR_UNICODE_SEQ,
                    'incomplete unicode escape sequence in string constant', lex.toks[lex.top]));
            } else {
                Integer seqStart = cur - state + 2;
                throw new ScanException(errorToken(
                    strErrCursor(lex.cursor, lineContinuationCount, lastContinuationCur, seqStart), 
                    lex.stream.substring(seqStart, cur), ERR_STR_HEX_SEQ,
                    'incomplete hex escape sequence in string constant', lex.toks[lex.top]));
            }
        }
        
        // verify that cur points at the correct terminating quote char:
        if (!(isDQ ? '"' : '\'').equals(streamArray[cur])) {
            if (cur < lex.streamLen) {
                throw new ScanException(errorToken(lex.cursor, lex.stream.substring(index, cur), ERR_BROKEN_STRING,
                                                    'illegal line-break in string constant', lex.toks[lex.top]));
            } else {
                throw new ScanException(errorToken(lex.cursor, lex.stream.substring(index, cur), ERR_UNTERM_STRING,
                                                    'unterminated string constant', lex.toks[lex.top]));
            }
        }
        
        // inline token construction:
        Token cursor = lex.cursor;
        cursor.ttype = STRING_LITERAL;
        Token tok = cursor.clone();
        cursor.index = cur + 1; // advance past the terminating quote char
        
        if (lineContinuationCount > 0) {
            cursor.line += lineContinuationCount;
            cursor.col = cur - lastContinuationCur + 1; // add 1 to get past the terminating quote char
        } else {
            cursor.col += cur - index + 1; // add 1 to get past the terminating quote char
        }
        
        if (parts.size() == 0) {
            tok.lexeme = lex.stream.substring(index, cur + 1);
            tok.stringLitParts.add(cur > index + 1 ? lex.stream.substring(index + 1, cur) : '');
            tok.stringLitCodes.add(0);
        } else {
            if (cur > lastPartEnd) {
                parts.add(lex.stream.substring(lastPartEnd, cur));
                codes.add(0);
            }
            tok.lexeme = lex.stream.substring(index, cur + 1);
            tok.stringLitParts = parts;
            tok.stringLitCodes = codes;
        }
        return tok;
    }
    
    static Token strErrCursor(Token startCursor, Integer lineContinuationCount, Integer lastContinuationCur, Integer cur) {
        Token inc = startCursor.clone();
        inc.index = cur;
        if (lineContinuationCount > 0) {
            inc.line += lineContinuationCount;
            inc.col = cur - lastContinuationCur;
        } else {
            inc.col += cur - startCursor.index;
        }
        return inc;
    }
    
    // when a scan-exception is thrown, the current lexer.cursor loc is expected to point at the error's source-code location, minus
    // any lead-boundary and offset:
    class ScanException extends Exception {
        Token errorTok;
        
        ScanException(Token errorTok) {
            this.errorTok = errorTok;
        }
    }
    
    // upon instantiation, we scan all tokens to be found in srcCode into the "toks" buffer
    // !! for the sake of efficiency, this may produce a toks array where toks.size() is greater than the actual # of
    // scanned tokens (i.e. it may be end-padded with nulls). however, it is guaranteed to have a terminating <EOF> token
    // before the end-padded nulls. parsers should interpret the encounter of an <EOF> as end-of-stream, OR may use lmt to
    // determine the <EOF> token -- they should not use toks.size():
    public static SOQLLexer newLexer(String srcCode) {
        SOQLLexer lex = ProtoLexer.clone();
        lex.stream = srcCode;
        lex.streamArray = srcCode.split('');
        // TODO: there won't be this extra empty-string element from split('') in later Apex API versions:
        if (lex.streamArray.size() > 0 && lex.streamArray[0].length() == 0) {
            lex.streamArray.remove(0);
        }
        lex.streamLen = srcCode.length();
        // !! append a terminating NUL char '\0', to allow simpler scanning logic that more gracefully handles tests that hit end-of-file
        // (e.g. so that we never cause ArrayIndexOutOfBounds by looking ahead 1 char in streamArray) -- note that some of these tests will
        // accept an actual \0 char (e.g. inside a string literal; inside a comment; inside RegExp), so they must include an additional
        // streamLen test to disambiguate a true source \0 from an EOF:
        lex.streamArray.add(String.fromCharArray(new Integer[]{ 0 }));
        
        Token cur = lex.cursor = new Token();
        cur.ttype = EMPTY;
        cur.line = CursorStartLineAdjust; //0;
        cur.col = CursorStartColAdjust; //0;
        cur.index = 0; //CursorStartIndexAdjust; //0;
        cur.leadLineBreaks = 0;
        cur.injected = false;
        
        lex.scanAll();
        return lex;
    }
    
    static SOQLLexer ProtoLexer = new SOQLLexer();

    // !! Starting offsets is a HACK to compensate for SOQLEvaluator prefixing a condition expression with 'FROM {targetType} WHERE '

    public static Integer CursorStartColAdjust = 0;
    public static Integer CursorStartLineAdjust = 0;
    //public static Integer CursorStartIndexAdjust = 0;

    public static void CursorAdjustForPrefix(String exprPrefix) {
        if (String.isBlank(exprPrefix)) {
            CursorAdjustReset();
        } else {
            String[] prefixLines = exprPrefix.split('\r\n|\r|\n');
            CursorStartLineAdjust = -(prefixLines.size() - 1);
            CursorStartColAdjust = -prefixLines[prefixLines.size() - 1].length();
            //CursorStartIndexAdjust = -exprPrefix.length();
        }
    }

    public static void CursorAdjustReset() {
        CursorStartColAdjust = 0;
        CursorStartLineAdjust = 0;
        //CursorStartIndexAdjust = 0;
    }
}