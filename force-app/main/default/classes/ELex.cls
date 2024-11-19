/*
 * Mike Ulveling
 *
 * Lexical Analyzer for Riskonnect Expression Language (Lexical Grammar)
 */
global class ELex {
    
    // each token id has an entry in this list; the value is its "expression routing/parsing-level", to be used by the parser. the parse-level is the
    // same as the op's expr level (0-based, e.g. Comma=0; Assign=1). note that all tokens which are not expression-routing infix/postfix operators
    // (e.g. '{') will have an entry value of -1, which dictates that the current expr-part shall be terminated:
    public static final Integer[] ExprLevelTable = new Integer[]{};
    public static Integer tokid = 0;

    static Integer tokid(Integer exprRoutingLvl) {
        return tokid(exprRoutingLvl, TKLASS_NONE);
    }

    static Integer tokid(Integer exprRoutingLvl, Integer classifications) {
        ExprLevelTable.add(exprRoutingLvl);
        TokenClassifications.add(classifications);
        return tokid++;
    }
    
    //public static final Integer PARSE_GOAL_OP   = 0;
    //public static final Integer PARSE_GOAL_DATA = 1;
    
    // and here, each entry is a bitfield that identifies that token's special classifications -- note these classifications are not mututally
    // exclusive:
    // 0   => a token with no special classifications
    // 2^0 => token may serve as a prefix operator (i.e. unary or new op)
    // 2^1 => token looks like data and thus sets a div context (vs. regexp context)
    // 2^2 => token can serve as a primary expr's data
    // 2^3 => token is an IdentifierName (identifiers, keywords, reserved words):
    public static final Integer[] TokenClassifications = new Integer[]{};
    // tokens with no special classification:
    public static final Integer TKLASS_NONE = 0;
    // tokens that can represent a unary prefix operator:
    public static final Integer TKLASS_PREFIX = 1;
    // tokens that look like "data", and thus a subsequent '/' char should be interpreted as a divide-op rather than a regexp-literal:
    public static final Integer TKLASS_SETS_GOAL_OP = 1 << 1;
    // tokens that can be accepted as a PrimaryExpression data node that can be resolved to a value in the parsing phase (e.g. string literal, regexp,
    // boolean values):
    public static final Integer TKLASS_PRIMARY_DATA = 1 << 2;
    // tokens that qualify as an ECMAScript5 IdentifierName (identifiers, keywords, reserved words):
    public static final Integer TKLASS_IDENT_NAME = 1 << 3;
    
    // empty token to serve as the "none" prior token before we've scanned our first token:
    public static final Integer EMPTY = tokid(-1);
    // the terminating "end-of-file" token:
    public static final Integer EOF = tokid(-1);
    // the terminating "error" token (i.e. token manifestation of a ScanException):
    public static final Integer ERROR = tokid(-1);

    // lexer/scanner error types:
    public static final Integer ERR_COMMENT_UNTERM        = 0;
    public static final Integer ERR_LOGICAL_AND_FALLBACK  = 1;
    public static final Integer ERR_LOGICAL_OR_FALLBACK   = 2;
    public static final Integer ERR_NUM_EXP_DIGIT         = 3;
    public static final Integer ERR_NUM_HEX_DIGIT         = 4;
    public static final Integer ERR_NUM_IDENT_SEP         = 5;
    public static final Integer ERR_REGEXP_IDENT_SEP      = 6;
    public static final Integer ERR_STRING_UNICODE_ESCAPE = 7;
    public static final Integer ERR_STRING_HEXADEC_ESCAPE = 8;
    public static final Integer ERR_STRING_BROKEN         = 9;
    public static final Integer ERR_STRING_UNTERM         = 10;
    public static final Integer ERR_ILLEGAL_CHAR          = 11;
    public static final Integer ERR_REGEXP_UNTERM         = 12;
    public static final Integer ERR_REGEXP_BROKEN         = 13;
    public static final Integer ERR_REGEXP_ILLEGAL_START  = 14;
    public static final Integer ERR_REGEXP_FLAGS          = 15;

    /*
    Expression levels (subject to future expansion; order and adjacency is what matters here): 

    -1 - top
     0 - comma
     1 - assign
     2 - ternary
     3 - logical OR
     4 - logical AND
     5 - equality/inequality
     6 - relational
     7 - additive
     8 - multiplicative
     9 - prefix
     10 - primary (?? member before primary?)
     11 - empty
    */

    // 1-char punctuators:
    public static final Integer COMMA         = tokid(0);
    public static final Integer COLON         = tokid(-1);
    public static final Integer SEMICOLON     = tokid(-1);
    public static final Integer DOT           = tokid(10); // primary
    public static final Integer OPEN_BRACKET  = tokid(10); // primary
    public static final Integer CLOSE_BRACKET = tokid(-1, TKLASS_SETS_GOAL_OP);
    public static final Integer OPEN_PAREN    = tokid(10); // primary
    public static final Integer CLOSE_PAREN   = tokid(-1, TKLASS_SETS_GOAL_OP);
    // expression-level operators & keywords:
    public static final Integer ASSIGNMENT          = tokid(1);
    //public static final Integer CONDITIONAL         = tokid(2);
    public static final Integer QUEST_MARK          = tokid(2);
    public static final Integer LOGICAL_OR          = tokid(3);
    public static final Integer LOGICAL_AND         = tokid(4);
    public static final Integer EQUALS              = tokid(5);
    public static final Integer NOT_EQUALS          = tokid(5);
    public static final Integer GREATER_THAN        = tokid(6);
    public static final Integer GREATER_THAN_EQUALS = tokid(6);
    public static final Integer LESS_THAN           = tokid(6);
    public static final Integer LESS_THAN_EQUALS    = tokid(6);
    public static final Integer PLUS                = tokid(7, TKLASS_PREFIX);
    public static final Integer MINUS               = tokid(7, TKLASS_PREFIX);
    public static final Integer MULTIPLY            = tokid(8);
    public static final Integer DIVIDE              = tokid(8);
    public static final Integer MODULUS             = tokid(8);
    public static final Integer LOGICAL_NOT         = tokid(-1, TKLASS_PREFIX); // unary prefix op; special handling
    public static final Integer BIT_NOT             = tokid(-1, TKLASS_PREFIX); // unary prefix op; special handling
    
    // complex tokens:
    public static final Integer IDENTIFIER  = tokid(-1, TKLASS_SETS_GOAL_OP | TKLASS_IDENT_NAME);
    public static final Integer HEXADEC_LIT = tokid(-1, TKLASS_SETS_GOAL_OP | TKLASS_PRIMARY_DATA);
    public static final Integer DECIMAL_LIT = tokid(-1, TKLASS_SETS_GOAL_OP | TKLASS_PRIMARY_DATA);
    public static final Integer STRING_LIT  = tokid(-1, TKLASS_SETS_GOAL_OP | TKLASS_PRIMARY_DATA);
    public static final Integer REGEXP_LIT  = tokid(-1, TKLASS_SETS_GOAL_OP | TKLASS_PRIMARY_DATA);
    
    // the following are special abstract token types, used only as placeholders for a partial-states by the scanner (not returned by 
    // the scanner); they both resolve to a DECIMAL_NUMBER:
    public static final Integer PLAIN_ZERO  = tokid(-1);
    public static final Integer DOTTED_ZERO = tokid(-1);

    // keywords, followed by future reserved words:
    public static final Integer KEYWORD_MINIMUM = tokid; // all keywords are >= this id
    public static final Integer KW_INSTANCEOF   = tokid(6, TKLASS_IDENT_NAME);
    public static final Integer KW_TRUE         = tokid(-1, (TKLASS_SETS_GOAL_OP | TKLASS_PRIMARY_DATA) | TKLASS_IDENT_NAME);
    public static final Integer KW_FALSE        = tokid(-1, (TKLASS_SETS_GOAL_OP | TKLASS_PRIMARY_DATA) | TKLASS_IDENT_NAME);
    public static final Integer KW_NULL         = tokid(-1, (TKLASS_SETS_GOAL_OP | TKLASS_PRIMARY_DATA) | TKLASS_IDENT_NAME);
    
    // future reserved words:
    public static final Integer RESERVED_WORD_MINIMUM = tokid; // all reserved words (including strict mode reserved) are >= this id
    // TODO: reserved words? 
    
    // transition states:
    // the "transition-state" bit is the 2^8 bit (256); the 7 bits below this can enumerate up to 255 different token types:
    static final Integer TS_BIT = 1 << 8;
    // use this mask with '&' to remove the lower token-type bits, thus revealing the transition-state:
    static final Integer TS_MASK = ~0 << 8;
    // use this mask with '&' to remove the upper transition-state bits, thus revealing the token-type (if any):
    static final Integer TOKEN_MASK = ~TS_MASK;
    
    static Integer tsid = 1;
    // signals that we need to try a 2-char lookup, and if that fails we can fallback to the token-type specified 
    // in the lower bits:
    static final Integer TS_NEXT       = tsid++ << 8;
    static final Integer TS_IDENTIFIER = tsid++ << 8;
    // we use special transition-states for strings so that we can differentiate between the SQ and DQ flavors:
    static final Integer TS_STRING_SQ  = tsid++ << 8;
    static final Integer TS_STRING_DQ  = tsid++ << 8;
    // a decimal number starting with an integer component, optionally followed by a decimal component and/or an exponent:
    static final Integer TS_DECIMAL_0  = tsid++ << 8;
    // a decimal number starting with a decimal component (no integer component), optionally followed by an exponent:
    static final Integer TS_DECIMAL_1  = tsid++ << 8;
    // a hexadecmal number with a "0x" prefix:
    static final Integer TS_HEXADEC    = tsid++ << 8;

    // using a hash map here would look more elegant, but the following scheme is far more performant (in Apex, indexOf is much faster than a Map
    // lookup, at least until the search string becomes extremely long
    // !! note that entries for letters and digits are generated and added in the following static block
    static String TransStateLookup1 = ',:[]()?~\'"$_!=><+-*%&|.0';
    // initial lookup; resolves 1 char of lookahead to a concrete token type, a transition-state (TS_NEXT indicates that an additional char of lookahead, 
    // at a minimum, is necessary), or null (i.e. not a legal "black" token):
    static final Integer[] TransStateTable1 = new Integer[]{
        COMMA,
        COLON,
        OPEN_BRACKET,
        CLOSE_BRACKET,
        OPEN_PAREN,
        CLOSE_PAREN,
        QUEST_MARK, //CONDITIONAL,
        BIT_NOT,
        TS_STRING_SQ,
        TS_STRING_DQ,
        TS_IDENTIFIER, //TS_COMPLEX | IDENTIFIER,
        TS_IDENTIFIER, //TS_COMPLEX | IDENTIFIER,
        TS_NEXT | LOGICAL_NOT,  // !, !=
        TS_NEXT | ASSIGNMENT,   // =, ==
        TS_NEXT | GREATER_THAN, // >, >=
        TS_NEXT | LESS_THAN,    // <, <=
        PLUS,
        MINUS,
        MULTIPLY,
        MODULUS,
        TS_NEXT | ERROR,     // & (&) => LOGICAL_AND,
        TS_NEXT | ERROR,     // | (|) => LOGICAL_OR,
        TS_NEXT | DOT,       // . (\d) => TS_DECIMAL_1
        TS_NEXT | PLAIN_ZERO // 0 (\d) => TS_DECIMAL_0, 0 (\.) => TS_NEXT | DOTTED_ZERO
    };
    // add transition-states for the usual ASCII digits [0-9] and letters [a-zA-Z]:
    static {
        for (Integer i=1; i <=9; i++) {
            TransStateLookup1 += i;
            TransStateTable1.add(TS_DECIMAL_0);
        }
        String alpha = 'abcdefghijklmnopqrstuvwxyz';
        String ch;
        for (Integer i=0; i < alpha.length(); i++) {
            TransStateLookup1 += (ch = alpha.mid(i, 1));
            TransStateTable1.add(TS_IDENTIFIER);
            TransStateLookup1 += (ch = ch.toUpperCase());
            TransStateTable1.add(TS_IDENTIFIER);
        }
    }
    // concats the most common whitespace chars with TransStateLookup1, so that the simple-boundary scanner loop can collect
    // as much information as possible in just 1 indexOf call plus 1 array-access:
    static final String WhiteBlackLookup = ' \t\n' + TransStateLookup1;
    static final String IdentTerminatorsLookup = ' \t\n,:;{}[]()?~\'"$_!=><+-*%&|^./\r' + String.fromCharArray(new Integer[]{ 0, 2028, 2029 });

    // lookup for tokens that require at least 2 chars of lookahead:
    static String TransStateLookup2 = '==!=>=<=&&||0.0e0E0x0X';
    static final Integer[] TransStateTable2 = new Integer[]{
        EQUALS, null,
        NOT_EQUALS, null,
        GREATER_THAN_EQUALS, null,
        LESS_THAN_EQUALS, null,
        LOGICAL_AND, null,
        LOGICAL_OR, null,
        TS_NEXT | DOTTED_ZERO, null, // 0. ([0-9]) => TS_DECIMAL_0 (0 int component followed by decimal component)
        TS_NEXT | ERROR, null, // 0e ([+\-][0-9]|[0-9]) => TS_DECIMAL_0 (0 int component followed by exponent)
        TS_NEXT | ERROR, null, // 0E ([+\-][0-9]|[0-9]) => TS_DECIMAL_0 (0 int component followed by exponent)
        TS_NEXT | ERROR, null, // 0x ([0-9a-fA-F]) => TS_HEXADEC
        TS_NEXT | ERROR, null  // 0X ([0-9a-fA-F]) => TS_HEXADEC
    };
    // add transition states for \.\d (e.g. '.9') and 0\d (e.g. '09'):
    static {
        for (Integer i=0; i <=9; i++) {
            TransStateLookup2 += '.' + i;
            TransStateTable2.add(TS_DECIMAL_1); // (\.[0-9]) => TS_DECIMAL_1
            TransStateTable2.add(null);
            // since a ch1=='0' is deferred to tsMap2, we must also account for all (min 2-char) decimal numbers with a leading 0:
            TransStateLookup2 += '0' + i;
            TransStateTable2.add(TS_DECIMAL_0); // (0[0-9]) => TS_DECIMAL_0
            TransStateTable2.add(null);
        }
    }

    // lookup for tokens that require at least 3 chars of lookahead:
    static String TransStateLookup3 = '0e+0e-0E+0E-';
    static final Integer[] TransStateTable3 = new Integer[]{
        TS_NEXT | ERROR, null, null,
        TS_NEXT | ERROR, null, null,
        TS_NEXT | ERROR, null, null,
        TS_NEXT | ERROR, null, null
    };
    static {
        // generate transition states for: 0e[0-9], 0E[0-9]
        for (String ch2 : new String[]{ '0e', '0E' }) {
            for (Integer i=0; i <= 9; i++) {
                TransStateLookup3 += ch2 + i;
                TransStateTable3.add(TS_DECIMAL_0);
                TransStateTable3.add(null);
                TransStateTable3.add(null);
            }
        }
        // generate transition states for: 0x[0-9a-fA-F], 0X[0-9a-fA-F]
        for (String ch2 : new String[]{ '0x', '0X' }) {
            for (String ch3 : '0123456789aAbBcCdDeEfF'.split('')) {
                TransStateLookup3 += ch2 + ch3;
                TransStateTable3.add(TS_HEXADEC);
                TransStateTable3.add(null);
                TransStateTable3.add(null);
            }
        }
    }

    // lookup for tokens that require at least 4 chars of lookahead (only decimal numbers that are a leading 0 followed 
    // by an exponent):
    static String TransStateLookup4 = '';
    static final Integer[] TransStateTable4 = new Integer[]{};
    static {
        // generate transition states for: 0e+[0-9], 0e-[0-9], 0E+[0-9], 0E-[0-9]
        for (String ch3 : new String[]{ '0e+', '0e-', '0E+', '0E-' }) {
            for (Integer i=0; i <= 9; i++) {
                TransStateLookup4 += ch3 + i;
                TransStateTable4.add(TS_DECIMAL_0);
                TransStateTable4.add(null);
                TransStateTable4.add(null);
                TransStateTable4.add(null);
            }
        }
    }
    
    static final Map<String, Integer> KeywordsMap = new Map<String, Integer>{
        'null'       => KW_NULL,
        'true'       => KW_TRUE,
        'false'      => KW_FALSE,
        'instanceof' => KW_INSTANCEOF
    };
    
    // !! note that the parser can identify strict-mode reserved tokens by the test: token.ttype >= STRICT_RESERVED_MINIMUM:
    static String KeywordsLookup = '';
    static Integer[] KeywordsTable;
    static Integer[] KeywordLenTable;
    static {
        String keywordsList = 'null true false instanceof';
        String[] Keywords = keywordsList.split(' ');
        KeywordsTable = new Integer[keywordsList.replaceAll('[ ]', '').length()];
        KeywordLenTable = new Integer[KeywordsTable.size()];
        for (String keyword: Keywords) {
            KeywordsTable[KeywordsLookup.length()] = KeywordsMap.get(keyword);
            KeywordLenTable[KeywordsLookup.length()] = keyword.length();
            KeywordsLookup += keyword;
        }
        // we add an extra entry at index=0 to seamlessly identify plain IDENTIFIER tokens; when indexing into this hash, add 1 to the result from
        // KeywordsLookup.indexOf(lexeme):
        KeywordsTable.add(0, IDENTIFIER);
        // insert a null simply to keep indexes in sync with KeywordsTable:
        KeywordLenTable.add(0, null);
    }

    static final String NullChar = String.fromCharArray(new Integer[]{ 0 });
    // in addition to unicode letters and unicode escape sequences, an identifier may start in a [$_]:
    static final String AdditionalIdentStartChars = '$_';
    // in addition to the unicode alphanumeric chars and [$_], we add the zero-width joiner (\u200D <ZWJ>) and non-joiner (\u200C <ZWNJ>) chars to
    // our "common" identifier parts:
    static final String AdditionalIdentPartChars = '$_' + String.fromCharArray(new Integer[]{ 8204, 8205 });
    
    static final String UnicodeSpecialLineTerminators = String.fromCharArray(new Integer[]{ 2028, 2029 });
    static final String NormalModeBreakingCharsSQ = '\'\n\r\\' + UnicodeSpecialLineTerminators;
    static final String NormalModeBreakingCharsDQ = '"\n\r\\' + UnicodeSpecialLineTerminators;
    static final String DecimalDigits = '0123456789.eE';
    static final String PlusMinusChars = '+-';
    public static final String HexadecimalDigits = '0123456789abcdef';
    
    // <Slash><LF><CR><LS><PS><SP><TAB><VTAB><FF><NBSP><BOM><Other Unicode Whitespace Chars [16]>
    // index > 4 indicates a whitespace char
    // index > 0 and <= 4 indicates a line-terminator
    // index == 0 indicates a forward-slash char
    static final String ComplexBoundaryLookup = '/\n\r' + UnicodeSpecialLineTerminators + ' \t' + String.fromCharArray(new Integer[]{ 11, 12, 160, 65279, 
            // additional unicode chars in the "common separator, space" category:
            5760, 6158, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8239, 8287, 12288
    });
    
    static final String CommentTypeLookup = '*/';
    static final String SingleLineCommentIndex = String.fromCharArray(new Integer[]{ 0 }) + '\n\r' + String.fromCharArray(new Integer[]{ 2028, 2029 });
    static final String MultiLineCommentLookup = String.fromCharArray(new Integer[]{ 0 }) + '*\n\r' + String.fromCharArray(new Integer[]{ 2028, 2029 });
    
    public String stream;
    String[] streamArray; // array of chars
    Integer streamLen;
    // !! cursor.ttype will hold the token-type of the prior token until the new token is verified and instantiated. 
    // for determining the next ECMAScript "goal" symbol: "InputElementDiv" or "InputElementRegExp", cursor.ttype crucially 
    // helps in the "easy" (and common) cases where we can disambiguate regular expression literals from the '/' and '/=' 
    // division operators purely in the scanner, without feedback from the parser. the hard cases (i.e. a '/' symbol
    // following a '++' or '--') will result in a "NEEDS_FEEDBACK" token to prompt the parser for contextual feedback and
    // a subsequent scanMore() call:
    Token cursor;
    
    // the starting token-stack size (i.e. lmt + 1) is 20; this will double as necessary:
    public Token[] toks = new Token[20];
    public Integer lmt = -1;
    Integer top = -1;
    public Integer next = 0;
    
    // scans all tokens from the source code into the tokens-stack, until we hit a terminating EOF, ERROR, or a NEEDS_FEEDBACK:
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
                    Boolean hasLead;
                    String ch1;
                    Integer 
                        index = cursor.index, 
                        tsIndex1;

                    cursor.leadLineBreaks = 0;
                    cursor.leadComments = null;
                    
                    // scan a leading token boundary (i.e. a "white" token) in parts:
                    // 1. try to scan a "simple" boundary part
                    // 2. if we're not looking at an unambiguous common "black" token start after step 1, then try to parse a "complex" boundary,
                    //    consisting of any combination of non-break space (including special unicode space chars), line-terminators (including
                    //    \r\n sequences and special unicode line-terminators), single-line comments, and multi-line comments.
                    // 3. after 2, we may or may not have parsed any lead boundary, but we must be looking at either a black-token, an illegal
                    //    token, or EOF; prepare for the next scanning stage.
                    // !! this loop is guaranteed not to iterate; it is used instead of a plain code-block because Apex does have labeled 
                    // statements and targeted breaks:
                    do {
                        // the following while loop attempts to scan consecutive 'simple' whitespace chars; this scenario should be by far more common
                        // than any other non-null boundary; if the boundary is not simple then we'll fallthrough to leverage a more robust (but
                        // slower) scaner. simple whitespace includes the space [ ], tab \t, and newline \n chars -- but not Microsoft's goddamned 
                        // \r\n, and not the special unicode chars:
                        Integer wbIndex;
                        Integer colStart = index;
                        
                        // common whitespace chars occupy the first 3 positions of WhiteBlackLookup; after that is all the common black-token start 
                        // chars -- thus, when we encounter a common "black" char, we can get its 1st transition-state index by simply subtracting 4 
                        // (backslash must fallthrough to more rigorous processing):
                        while ((wbIndex = WhiteBlackLookup.indexOf(streamArray[index])) < 3 && wbIndex > -1) {
                            index++;
                            // if we got a \n char:
                            if (wbIndex == 2) {
                                cursor.leadLineBreaks++;
                                cursor.col = 0;
                                colStart = index;
                            }
                        }
                        cursor.col += index - colStart;
                        
                        // if we scanned in a simple boundary part, then index points at the next char past this part:
                        if (index > cursor.index) {
                            hasLead = true;
                            // the vast majority of the time after we scan a simple whitespace boundary part, we'll see an unambiguously 'black' token 
                            // start char immediately following it; if this is the case then short-circuit out of the boundary loop.
                            // !! note that our result tsIndex1 will be re-used in the subsequent black-token scanning logic, to save an array lookup; 
                            // also note that we must set ch1 for the next state.
                            // !! note that if wbIndex - 4 > -1 then we got an unambiguous 'black' char that can be easily identified; if < -1 then 
                            // it is something more difficult to reckon with:
                            if ((tsIndex1 = wbIndex - 4) > -1) {
                                ch1 = streamArray[index];
                                break;
                            }
                        // else, we didn't parse a simple boundary part; if we're looking at the start of a token that is unambiguously a "black" 
                        // token, then we have no leading boundary and we can proceed with scanning the black token.
                        // !! note that our result tsIndex1 will be re-used in the subsequent black-token scanning logic, to save a hash lookup:
                        // !! note that if wbIndex - 4 > -1 then we got an unambiguous 'black' char that can be simply mapped; if < -1 then it is 
                        // something difficult:
                        } else if ((tsIndex1 = wbIndex - 4) > -1) {
                            hasLead = false;
                            ch1 = streamArray[index];
                            break;
                        }
                        
                        // else, we didn't parse a simple boundary and we couldn't easily determine whether we're looking at an uncommon black token 
                        // start or a complex boundary part (including runs of multiple boundaries, e.g. comments followed by space/line-breaks and 
                        // then more comments); we must run the following rigorous (and slower) scanning logic: 
                        Integer boundaryType;
                        while ((boundaryType = ComplexBoundaryLookup.indexOf(streamArray[index])) > -1) {
                            // a forward-slash:
                            if (boundaryType == 0) {
                                Integer commentType = CommentTypeLookup.indexOf(streamArray[index + 1]);
                                // if the '/' does not begin a comment, then it must indicate a black-token (e.g. DIVIDE, REGEXP_LIT); break out of 
                                // this loop (and subsequently, the main boundary loop):
                                if (commentType < 0) {
                                    break;
                                // multi-line comment:
                                } else if (commentType == 0) {
                                    // store the starting location of the comment:
                                    Integer 
                                        cmmtStartIndex = index,
                                        cmmtStartCol = cursor.col,
                                        cmmtStartLine = cursor.line + cursor.leadLineBreaks;
                                    
                                    colStart = index;
                                    // advance past the '/*':
                                    index += 2;

                                    do {
                                        Integer commentCharType = MultiLineCommentLookup.indexOf(streamArray[index]);
                                        // plain comment char:
                                        if (commentCharType < 0) {
                                            index++;
                                        // if we got a line-break in the comment:
                                        } else if (commentCharType > 1) {
                                            cursor.col = 0;
                                            cursor.leadLineBreaks++;
                                            // as always, check for a \r\n sequence:
                                            if (commentCharType == 2 && '\n' == streamArray[index + 1]) {
                                                index += 2;
                                            } else {
                                                index++;
                                            }
                                            colStart = index;
                                        // when encountering a '*' char, we must check for a subsequent '/'
                                        } else if (commentCharType == 1) {
                                            // '*' followed by a '/' - we've found the end of the comment:
                                            if ('/' == streamArray[index + 1]) {
                                                index += 2;
                                                String commentText = stream.substring(cmmtStartIndex, index);
                                                if (cursor.leadComments == null) {
                                                    cursor.leadComments = new String[]{ commentText };
                                                } else { 
                                                    cursor.leadComments.add(commentText);
                                                }
                                                // this break represents the only legal ending alternative for a multi-line comment; if we reach here then increment 
                                                // the cursor to point just past the end of this comment:
                                                break;
                                            // else it was just a plain '*' char; continue scanning the comment:
                                            } else {
                                                index++;
                                            }
                                        // if we're looking at a \0, then check for a possible EOF:
                                        } else {
                                            if (index >= streamLen) {
                                                // for proper error-location reporting, we need to revert the cursor back to the start of this multi-line comment:
                                                //Token cmmtLoc = cursor.clone();
                                                cursor.index = cmmtStartIndex;
                                                cursor.col = cmmtStartCol;
                                                cursor.line = cmmtStartLine;
                                                Token penTok = top > -1 ? toks[top] : null;
                                                throw new ScanException(
                                                    errorToken(this, streamLen - cmmtStartIndex, ERR_COMMENT_UNTERM,
                                                        'unterminated multi-line comment'));
                                            // else this really was an actual \0 char embedded in the comment:
                                            } else {
                                                index++;
                                            }
                                        }
                                    } while (true);
                                    cursor.col += index - colStart;
                                    
                                // single-line comment:
                                } else {
                                    Integer commentStart = index;
                                    index += 2;
                                    do {
                                        Integer commentCharType = SingleLineCommentIndex.indexOf(streamArray[index]);
                                        // plain comment char:
                                        if (commentCharType < 0) {
                                            index++;
                                        // end of comment when we encounter a line-terminator:
                                        } else if (commentCharType > 0) {
                                            String commentText = stream.substring(commentStart, index);
                                            if (cursor.leadComments == null) {
                                                cursor.leadComments = new String[]{ commentText };
                                            } else { 
                                                cursor.leadComments.add(commentText);
                                            }
                                            break;
                                        // if we're looking at a \0, then check for a possible EOF:
                                        } else {
                                            // verify we haven't hit EOF:
                                            if (index < streamLen) {
                                                index++;
                                            } else {
                                                break;
                                            }
                                        }
                                    } while (true);
                                    cursor.col += index - commentStart;
                                }

                            // a line-terminator:
                            } else if (boundaryType < 5) {
                                cursor.col = 0;
                                cursor.leadLineBreaks++;
                                // try to identify a \r\n sequence:
                                if (boundaryType == 2 && '\n' == streamArray[index + 1]) {
                                    index += 2;
                                } else { 
                                    index++;
                                }
                            // a whitespace char:
                            } else {
                                cursor.col++;
                                index++;
                            }
                        }
                        
                        // at this point, we're guaranteed to have scanned all of the boundary (if any); prepare for the next scanning stage:
                        ch1 = streamArray[index];
                        hasLead = hasLead == true || index > cursor.index;
                        // TODO: this makes the 2nd time calling (WhiteBlackLookup|TransStateLookup1).indexOf on the same char in the case of a no-
                        // boundary with a divide op, regexp, or identifier starting in a non-ASCII Unicode Letter -- perhaps this can be avoided:
                        tsIndex1 = TransStateLookup1.indexOf(ch1);
                        break;
                        
                    // end of lead-boundary scanner; see above how we will never enter a 2nd iteration:
                    } while (true);
                    
                    // advance cursor.index so that it points to the 1st char past the lead-boundary:
                    if (hasLead) {
                        // !! update index and increment line, but col has already been updated
                        cursor.index = index;
                        cursor.line += cursor.leadLineBreaks;
                    }
                    // check to see if we're at EOF after advancing past the boundary:
                    if (index >= streamLen) {
                        toks[++top] = eofToken(cursor, top > -1 ? toks[top] : null);
                        break;
                    }

                    // !! note that due to the streamlined logic, we are guaranteed to have the current tsIndex1 already set from the above logic;
                    // if tsIndex1 is > -1, then ch1 must have matched either an unambiguous 1-char black token or a transition-state:
                    if (tsIndex1 > -1) {
                        Integer tsRes1 = TransStateTable1[tsIndex1];
                        // if ch1's table lookup value is below TS_BIT, then we've unambiguously matched a 1-char operator token (ttype defined by 
                        // the lookup value's first 8 bits); create and return it immediately:
                        if (tsRes1 < TS_BIT) {
                            // construct the new token inline, to save a call:
                            cursor.ttype = tsRes1;
                            Token tok = cursor.clone();
                            cursor.index += 1;
                            cursor.col += 1;
                            tok.lexeme = ch1;
                            toks[++top] = tok;
                            continue;
                        
                        // else if the TS_NEXT flag is on, then we need at least a 2nd char of lookahead to resolve this token:
                        } else if ((tsRes1 & TS_MASK) == TS_NEXT) {
                            Integer tsIndex2, tsRes2;
                            String ch2 = stream.mid(index, 2);
                            if ((tsIndex2 = TransStateLookup2.indexOf(ch2)) > -1 && (tsRes2 = TransStateTable2[tsIndex2]) != null) {
                                // if we matched a 2-char operator token:
                                if (tsRes2 < TS_BIT) {    
                                    cursor.ttype = tsRes2;
                                    Token tok = cursor.clone();
                                    cursor.index += 2;
                                    cursor.col += 2;
                                    tok.lexeme = ch2;
                                    toks[++top] = tok;
                                    continue;
                                // else if we require a 3rd char of lookahead:
                                } else if ((tsRes2 & TS_MASK) == TS_NEXT) {
                                    Integer tsIndex3, tsRes3;
                                    String ch3 = stream.mid(index, 3);
                                    if ((tsIndex3 = TransStateLookup3.indexOf(ch3)) > -1 && (tsRes3 = TransStateTable3[tsIndex3]) != null) {
                                        // if 3-char lookup matched, then its tsRes3 code value must be IN: (TS_NEXT | ERROR, TS_DECIMAL_0, TS_HEXADEC)
                                        if ((tsRes3 & TS_MASK) == TS_NEXT) {
                                            Integer tsIndex4, tsRes4;
                                            String ch4 = stream.mid(index, 4);
                                            if ((tsIndex4 = TransStateLookup4.indexOf(ch4)) > -1 && (tsRes4 = TransStateTable4[tsIndex4]) != null) {
                                                // ch4 matches: (0[eE][+\-][0-9])
                                                if (tsRes4 == TS_DECIMAL_0) {
                                                    // scan a decimal, starting at the signed exponent component (state == 2):
                                                    toks[++top] = scanDecimalNum(this, 2, index, index + 4);
                                                    continue;
                                                } else {
                                                    System.assert(false, 'Whoops! Missing legal alternative handling for 4-char lookup "' + ch4 + 
                                                        '" that didn\'t match TS_DECIMAL_0; TS code: ' + tsRes4);
                                                }
                                            // else if no 4-char lookup match, then we fallback to ERROR (which is currently the only alternative):
                                            } else {
                                                // ch3 IN: (0e+, 0e-, 0E+, 0E-)
                                                throw new ScanException(errorToken(this, 3, ERR_NUM_EXP_DIGIT,
                                                    'exponential notation ' + ch3 + ' must be followed by a digit'));
                                            }
                                        // ch3 matches: /0[eE][0-9]/
                                        } else if (tsRes3 == TS_DECIMAL_0) {
                                            // scan a decimal, starting at the unsigned exponent component (state == 2):
                                            toks[++top] = scanDecimalNum(this, 2, index, index + 3);
                                            continue;
                                        // ch3 matches: /0[xX][0-9]/
                                        } else if (tsRes3 == TS_HEXADEC) {
                                            toks[++top] = scanHexNumber(this, index);
                                            continue;
                                        } else {
                                            System.assert(false, 'Whoops! Missing legal alternative handling for 3-char lookup "' + ch3 + 
                                                '" that didn\'t match TS_NEXT, TS_DECIMAL_0, or TS_HEXADEC; TS code: ' + tsRes3);
                                        }
                                    // else if the 3-char lookahead failed to match, then we fallback to the 2-char simple token type or ERROR:
                                    } else {
                                        cursor.ttype = tsRes2 & TOKEN_MASK;
                                        if (cursor.ttype == DOTTED_ZERO) {
                                            // create the "0." token inline:
                                            Token tok = cursor.clone();
                                            tok.lexeme = ch2;
                                            tok.value = '0';
                                            cursor.index += 2;
                                            cursor.col += 2;
                                            toks[++top] = tok;
                                            continue;
                                        } else if (cursor.ttype == ERROR) {
                                            if (ch2 == '0e') {
                                                throw new ScanException(errorToken(this, 2, ERR_NUM_EXP_DIGIT,
                                                    'exponential notation ' + ch2 + ' must be followed by a digit'));
                                            } else if (ch2 == '0x') {
                                                throw new ScanException(errorToken(this, 2, ERR_NUM_HEX_DIGIT,
                                                    'hexadecimal notation ' + ch2 + ' must be followed by a digit'));
                                            } else {
                                                System.assert(false, 'Whoops! Missing handing for failed 3-char token lookup "' + ch3 + 
                                                    '" with a 2-char ERROR fallback');
                                            }
                                        } else {
                                            System.assert(false, 'Whoops! Missing handing for failed 3-char token lookup "' + ch3 + 
                                                '" with 2-char fallback token: ' + cursor.ttype);
                                        }
                                    }
                                // 2-char transition state TS_DECIMAL_0; ch2 matches (0[0-9]):
                                } else if (tsRes2 == TS_DECIMAL_0) {
                                    // scan a decimal, past the 2 lookahead chars (0[0-9]), starting in the integer component state (state == 0):
                                    toks[++top] = scanDecimalNum(this, 0, index, index + 2);
                                    continue;
                                // 2-char transition state TS_DECIMAL_1 ch2 matches (\.[0-9]):
                                } else if (tsRes2 == TS_DECIMAL_1) {
                                    // scan a decimal, past the 2 lookahead chars (\.[0-9]), starting in the decimal component state (state == 1):
                                    toks[++top] = scanDecimalNum(this, 1, index, index + 2);
                                    continue;
                                } else {
                                    System.assert(false, 'Whoops! Missing legal alternative handling for 2-char lookup "' + ch2 + 
                                        '" that didn\'t match TS_NEXT, TS_DECIMAL_0, or TS_DECIMAL_1; TS code: ' + tsRes2);
                                }

                            // else if no 2-char lookahead token-type match, then we fallback to the 1-char simple token type or ERROR:
                            } else {
                                cursor.ttype = tsRes1 & TOKEN_MASK;
                                if (cursor.ttype == ERROR) {
                                    if (ch1 == '&') {
                                        throw new ScanException(errorToken(this, 2, ERR_LOGICAL_AND_FALLBACK,
                                            'AND operator "&&" is the only valid alternative for a lead & character'));
                                    } else if (ch1 == '|') {
                                        throw new ScanException(errorToken(this, 2, ERR_LOGICAL_OR_FALLBACK,
                                            'OR operator "||" is the only valid alternative for a lead | character'));
                                    // the above branches must be complete to assure the following default branch is unreachable:
                                    } else {
                                        System.assert(false, 'Whoops! Missing handing for failed 2-char token lookup "' + ch2 + 
                                            '" with a 1-char ERROR fallback');
                                    }
                                // fallback to a concrete 1-char operator token:
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
                            }
                        // handle 1-char transition states other than TS_NEXT:
                        } else if (tsRes1 == TS_IDENTIFIER) {
                            //Boolean sepError = !hasLead && (cursor.ttype == HEXADEC_LIT || cursor.ttype == DECIMAL_LIT || cursor.ttype == REGEXP_LIT);
                            Boolean sepError = cursor.ttype == DECIMAL_LIT || cursor.ttype == REGEXP_LIT;
                            // we already know the 1st char is in the set [$_a-zA-Z], since we got we got a tsRes1 and these are the only 
                            // identifier start-chars in tsIndex1. thus, we immediately advance past it the start char, then scan for every
                            // subsequent legal identifier char:
                            Integer cur = index + 1;
                            // note that isAlphanumeric does indeed identify extended unicode letters and digits:
                            while (streamArray[cur].isAlphanumeric() || AdditionalIdentPartChars.contains(streamArray[cur])) {
                                cur++;
                            }
                            String lexeme = stream.substring(index, cur);
                            // for identifiers, we must attempt to resolve the lexeme to a keyword/reserverd-word -- unfortunately this 
                            // requires incurring the expense of an extra hash lookup:
                            // if the lexeme is a keyword, then the following logic will change ttype from IDENTIFIER to the appropriate
                            // KW_ or RW_ type:
                            Integer lookupIndex = KeywordsLookup.indexOf(lexeme) + 1;
                            cursor.ttype = KeywordsTable[lookupIndex];
                            // if we matched into the keyword lookup, then make sure would lexeme is the correct length for that keyword (i.e. 
                            // we must match the whole keyword, not just the start of the keyword):
                            if (cursor.ttype == null || cursor.ttype != IDENTIFIER && KeywordLenTable[lookupIndex] != cur - index) {
                                cursor.ttype = IDENTIFIER;
                            }
                            Token tok = cursor.clone();
                            cursor.index = cur;
                            cursor.col += cur - index;
                            tok.lexeme = lexeme;
                            toks[++top] = tok;
                            if (sepError) {
                                // there's guaranteed to be a previous number token because of the sepError condition:
                                Token prevTok = toks[top - 1];
                                Token identTok = toks[top];
                                // note that, in a break from tradition, we actually use the previous number token as the error location here:
                                throw new ScanException(errorToken(identTok, identTok.lexeme, 
                                    prevTok.ttype == REGEXP_LIT ? ERR_REGEXP_IDENT_SEP : ERR_NUM_IDENT_SEP,
                                    //'space separator is required between prior ' + 
                                    //(prevTok.ttype == REGEXP_LIT ? 'regular expression' : prevTok.ttype == HEXADEC_LIT ? 'hexadecimal number' : 'number') + 
                                    //' and start of identifer ' + identTok.lexeme, prevTok));
                                    'identifier ' + identTok.lexeme + ' cannot directly follow a ' + (prevTok.ttype == REGEXP_LIT ? 'regular expression' : 'number'), null));
                            } else {
                                continue;
                            }
                        // 2-char transition state TS_DECIMAL_0; ch1 matches ([1-9]):
                        } else if (tsRes1 == TS_DECIMAL_0) {
                            // scan a decimal, past the 1 lookahead char ([1-9]), starting in the integer component state (state == 0):
                            toks[++top] = scanDecimalNum(this, 0, index, index + 1);
                            continue;
                        } else if (tsRes1 == TS_STRING_DQ) {
                            toks[++top] = scanStringLit(this, index, index + 1, true);
                            continue;
                        } else if (tsRes1 == TS_STRING_SQ) {
                            toks[++top] = scanStringLit(this, index, index + 1, false);
                            continue;
                        } else {
                            System.assert(false, 'Whoops! Missing legal alternative handling for 1-char lookup "' + ch1 + 
                                '" that didn\'t match TS_NEXT, TS_IDENTIFIER, TS_DECIMAL_0, TS_STRING_DQ, or TS_STRING_SQ; TS code: ' + tsRes1);
                        }
                    // else, we either have an illegal token lead char, or a "difficult" token -- the latter being either a division op, a
                    // regexp, or an identifier with a lead char outside the ASCII range:
                    } else {
                        // '/' is difficult because of the ambiguity between DIVIDE and REGEXP_LIT. the current grammar does NOT require contextual 
                        // feedback from the parser (i.e. is the goal token an operator or data?); this may change in the future:
                        if ('/' == ch1) {
                            Integer priorType = cursor.ttype;
                            Token goalTok;
                            // use the prior token's bitfield class flags to determine whether it sets a parser goal of "operator" (i.e. DIVIDE) for the 
                            // next token:
                            if ((TokenClassifications[priorType] & TKLASS_SETS_GOAL_OP) > 0) {
                                // TODO: enhance this logic to detect ch2 matching ASSIGN_DIVIDE, if we add that op...
                                goalTok = newToken(cursor, DIVIDE, ch1, null, null, null);
                            // else a parse goal of "data" is implied; scan a regexp (TODO: if grammar is enhanced with a code block close brace, an 
                            // increment op, or a decrement op, then a condition will need to be added here to require parser feeback after those 
                            // tokens):
                            } else {
                                goalTok = scanRegexp(this, index);
                            }
                            toks[++top] = goalTok;
                            continue;
                        // an identifier may have slipped through the cracks with a lead char that is a unicode letter outside the traditional ASCII
                        // range; fortunately the Apex String class has a native method to match unicode letters:
                        } else if (ch1.isAlpha()) {
                            // see ECMA-262 7.8.3:
                            //Boolean numSepError = !hasLead && (cursor.ttype == HEXADEC_LIT || cursor.ttype == DECIMAL_LIT);
                            Boolean numSepError = cursor.ttype == REGEXP_LIT || cursor.ttype == DECIMAL_LIT;
                            Integer cur = index + 1;
                            // note that isAlphanumeric does indeed identify extended unicode letters and digits:
                            while (streamArray[cur].isAlphanumeric() || AdditionalIdentPartChars.contains(streamArray[cur])) {
                                cur++;
                            }
                            String lexeme = stream.substring(index, cur);
                            // for identifiers, we must attempt to resolve the lexeme to a keyword/reserverd-word -- unfortunately this requires 
                            // incurring the expense of an extra hash lookup: if the lexeme is a keyword, then the following logic will change ttype 
                            // from IDENTIFIER to the appropriate KW_ or RW_ type:
                            Integer lookupIndex = KeywordsLookup.indexOf(lexeme) + 1;
                            cursor.ttype = KeywordsTable[lookupIndex];
                            // if we matched into the keyword lookup, then make sure would lexeme is the correct length for that keyword (i.e. 
                            // we must match the whole keyword, not just the start of the keyword):
                            if (cursor.ttype == null || cursor.ttype != IDENTIFIER && KeywordLenTable[lookupIndex] != cur - index) {
                                cursor.ttype = IDENTIFIER;
                            }
                            Token tok = cursor.clone();
                            cursor.index = cur;
                            cursor.col += cur - index;
                            tok.lexeme = lexeme;
                            toks[++top] = tok;
                            if (numSepError) {
                                // there's guaranteed to be a previous number token because of the numSepError condition:
                                Token prevTok = toks[top - 1];
                                Token identTok = toks[top];
                                throw new ScanException(errorToken(identTok, identTok.lexeme, 
                                    prevTok.ttype == REGEXP_LIT ? ERR_REGEXP_IDENT_SEP : ERR_NUM_IDENT_SEP,
                                    //'space separator is required between prior ' + 
                                    //(prevTok.ttype == REGEXP_LIT ? 'regular expression' : prevTok.ttype == HEXADEC_LIT ? 'hexadecimal number' : 'number') + 
                                    //' and start of identifer ' + identTok.lexeme, prevTok));
                                    'identifier ' + identTok.lexeme + ' cannot directly follow a ' + (prevTok.ttype == REGEXP_LIT ? 'regular expression' : 'number'), null));

                            } else {
                                continue;
                            }
                        }
                    }
                    // crud, I guess we have an illegal token:
                    throw new ScanException(errorToken(this, 1, ERR_ILLEGAL_CHAR,
                        'unexpected lead character "' + streamArray[index] + '" has no legal alternative'));
                }
            // main scanToken loop; broken upon encounter of an ERROR or EOF token:
            } while (true);
        } catch (ScanException e) {
            // easy peasy:
            toks[++top] = e.errorTok;
        } finally {
            // clear out some of the input text to save heap space:
            // !! keep stream around to validate Directive Prologues and to provide the literal source code for functions:
            //stream = null;
            streamArray = null;
        }
    }

    // takes the starting state as a parameter, since in some cases we wish to start scanning after a decimal:
    static Token scanDecimalNum(Elex lex, Integer state, Integer index, Integer cur) {
        String[] streamArray = lex.streamArray;
        Integer digitType;
        // states:
        // 0 => start state; valid integer part
        // 1 => decimal part; valid
        // 2 => exponent, not yet valid (needs at least 1 digit)
        // 3 => exponent, valid
        // scan [\.0-9eE] chars:
        while ((digitType = DecimalDigits.indexOf(streamArray[cur])) > -1) {
            // we got a digit [0-9]:
            if (digitType < 10) {
                // a digit on an exponent makes it valid:
                if (state == 2) {
                    state = 3;
                }
            // we got a '.' char:
            } else if (digitType == 10) {
                // only state 0 accepts a decimal:
                if (state != 0) {
                    break;
                // state 0 proceeds to state 1 when it gets a decimal:
                } else {
                    state = 1;
                }
            // else, we must have an [eE] exponent:
            } else {
                // we can't accept another exponent if we're already in that state:
                if (state > 1) {
                    break;
                }
                // go directly to state 2:
                state = 2;
                // check for a [+-] sign, and advance past it:
                if (PlusMinusChars.indexOf(streamArray[cur + 1]) > -1) {
                    cur++;
                }
            }
            cur++;
        }
        // a decimal number cannot end in an [eE] that does not have 1 or more subsequent exponent digits:
        if (state == 2) {
            String errLexeme = lex.stream.substring(index, Math.min(cur, lex.streamLen));
            throw new ScanException(errorToken(lex, cur - index, ERR_NUM_EXP_DIGIT,
                'exponential notation ' + errLexeme + ' must be followed by a digit'));
        }
        Token cursor = lex.cursor;
        cursor.ttype = DECIMAL_LIT;
        Token tok = cursor.clone();
        cursor.index = cur;
        cursor.col += cur - index;
        tok.lexeme = lex.stream.substring(index, cur);
        return tok;
    }
    
    static Token scanHexNumber(Elex lex, Integer index) {
        Integer cur = index + 2;
        String[] streamArray = lex.streamArray;
        while (HexadecimalDigits.indexOfIgnoreCase(streamArray[cur]) > -1) {
            cur++;
        }
        // inline token construction:
        Token cursor = lex.cursor;
        cursor.ttype = HEXADEC_LIT;
        Token tok = cursor.clone();
        //tok.lexeme = lex.stream.substring(index + 2, cur);
        tok.lexeme = lex.stream.substring(index, cur);
        cursor.index = cur;
        cursor.col += cur - index;
        return tok;
    }
    
    static final String StringEscapeTypesLookup = '0xu\n\r' + UnicodeSpecialLineTerminators + '\'"\\bfnrtv';
    static final String[] StringEscapeTypeTable = new String[]{ NullChar, null, null, null, null, null, null, '\'', '"', '\\', '\b', '\f', '\n', '\r', '\t', String.fromCharArray(new Integer[]{ 11 }) };
    
    // rigorously scans string literals according to the ECMA-262 spec
    static Token scanStringLit(Elex lex, Integer index, Integer cur, Boolean isDQ) {
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
        // 6 => in a hex esc-sequence; has 1 digits; invalid until we get 2
        String[] parts = new String[]{}; // processed parts; to be joined on final token creation
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
                } else if ('\\' == ch) {
                    Integer escType = StringEscapeTypesLookup.indexOf(streamArray[cur + 1]);
                    if (escType > -1) {
                        if (cur > lastPartEnd) {
                            ch = lex.stream.substring(lastPartEnd, cur);
                            parts.add(ch);
                        }
                        // single-char escape:
                        if (escType > 6) {
                            parts.add(StringEscapeTypeTable[escType]);
                            lastPartEnd = cur = cur + 2;
                        // line continuation:
                        } else if (escType > 2) {
                            // check for a stupid M$-Windows \r\n line-break sequence:
                            if (escType == 4 && '\n' == streamArray[cur + 2]) {
                                cur = cur += 3;
                            } else { 
                                cur += 2;
                            }
                            lineContinuationCount++;
                            lastContinuationCur = lastPartEnd = cur;
                        // unicode escape sequence:
                        } else if (escType == 2) {
                            state = 1;
                            cur += 2;
                        // hex escape sequence:
                        } else if (escType == 1) {
                            state = 5;
                            cur += 2;
                        // null-char sequence: 
                        } else if (escType == 0) {
                            parts.add(StringEscapeTypeTable[0]);
                            lastPartEnd = cur = cur + 2;
                        }
                        
                    // else it must be a non-escape:
                    } else {
                        parts.add(ch);
                    }
                    
                // else this must be either a line-break (illegal) or a terminating quote char (must match the start quote) -- we'll check it 
                // after we break out of this scanning loop:
                } else {
                    break;
                }
                
            // else, we are in a unicode escape sequence:
            } else if (state < 5) {
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
                        lastPartEnd = ++cur;
                        continue;
                    }
                    cur++;
                } else {
                    throw new ScanException(errorToken(lex, cur - index, ERR_STRING_UNICODE_ESCAPE,
                        'string value\'s unicode escape must be followed by exactly 4 digits (got ' + (state - 1) + ')'));
                }

            // else, we must be in a hex escape sequence:
            } else {
                Integer digitVal = HexadecimalDigits.indexOfIgnoreCase(streamArray[cur]);
                if (digitVal > -1) {
                    if (state == 5) {
                        state = 6;
                        hexValue = digitVal << 4;
                    } else {
                        state = 0;
                        hexValue += digitVal;
                        parts.add(String.fromCharArray(new Integer[] { hexValue }));
                        lastPartEnd = ++cur;
                        continue;
                    }
                    cur++;
                } else {
                    throw new ScanException(errorToken(lex, cur - index, ERR_STRING_HEXADEC_ESCAPE,
                        'string value\'s hexadecimal escape must be followed by exactly 2 digits (got ' + (state - 5) + ')'));
                }
            }
        } while (true);
        
        if (state > 0) {
            if (state < 5) {
                throw new ScanException(errorToken(lex, cur - index, ERR_STRING_UNICODE_ESCAPE,
                    'string value\'s unicode escape must be followed by exactly 4 digits (got ' + (state - 1) + ')'));
            } else {
                throw new ScanException(errorToken(lex, cur - index, ERR_STRING_HEXADEC_ESCAPE,
                    'string value\'s hexadecimal escape must be followed by exactly 2 digits (got ' + (state - 5) + ')'));
            }
        }

        // verify that cur points at the correct terminating quote char:
        if ((isDQ ? '"' : '\'') != streamArray[cur]) {
            if (cur >= lex.streamLen) {
                throw new ScanException(errorToken(lex, cur - index, ERR_STRING_UNTERM,
                    'unterminated string value'));
            } else {
                throw new ScanException(errorToken(lex, cur - index, ERR_STRING_BROKEN,
                    'illegal line-break in string value'));
            }
        }
        
        // inline token construction:
        Token cursor = lex.cursor;
        cursor.ttype = STRING_LIT;
        Token tok = cursor.clone();
        cursor.index = cur + 1; // advance past the terminating quote char
        if (lineContinuationCount > 0) {
            cursor.line += lineContinuationCount;
        }
        
        if (lineContinuationCount > 0) {
            cursor.col = cur - lastContinuationCur + 1; // add 1 to get past the terminating quote char
        } else {
            cursor.col += cur - index + 1; // add 1 to get past the terminating quote char
        }

        // raw lexeme includes enclosing quotes and unprocessed escape sequences:
        tok.lexeme = lex.stream.substring(index, cur + 1);
        if (parts.size() == 0) { 
            tok.value = lex.stream.substring(index + 1, cur);
        } else {
            if (cur > lastPartEnd) {
                parts.add(lex.stream.substring(lastPartEnd, cur));
            }
            tok.value = String.join(parts, '');
        }
        return tok;
    }
    
    // the first two -- backslash and '[' -- are valid start chars; the \0 may be valid or may indicate EOF; the remaining chars represent invalid
    // start chars:
    static final String RegexpStartCharsLookup = '\\[' + String.fromCharArray(new Integer[]{ 0 }) + '*/\n\r' + String.fromCharArray(new Integer[]{ 2028, 2029 });
    static final String RegexpCharsLookup = '\\[]/' + String.fromCharArray(new Integer[]{ 0 }) + '\n\r' + String.fromCharArray(new Integer[]{ 2028, 2029 });
    
    static Token scanRegexp(Elex lex, Integer index) {
        String[] streamArray = lex.streamArray;
        // advance past the lead '/':
        Integer cur = index + 1;
        Integer charType = RegexpStartCharsLookup.indexOf(streamArray[cur++]);
        Integer state;
        // states:
        // 0 => normal state
        // 1+ => in char-class; values beyond 1 indicate nesting
        
        // scan the regexp lead char or lead escape-sequence:
        if (charType < 0) {
            state = 0;
        // a lead escape-sequence:
        } else if (charType == 0) {
            state = 0;
            // look at the next char after the backslash; accept anything other than line-terminators or EOF:
            charType = RegexpCharsLookup.indexOf(streamArray[cur++]);
            if (charType > 4 || charType == 4 && cur >= lex.streamLen) {
                // we backtrack so that the next iteration can choke on the illegal line-terminator or EOF:
                cur--;
            }
        // a lead '[' denotes the start of a char-class:
        } else if (charType == 1) {
            state = 1;
        // check for EOF on a lead \0:
        } else if (charType == 2) {
            if (cur >= lex.streamLen) {
                throw new ScanException(errorToken(lex, cur - index, ERR_REGEXP_UNTERM,
                    'unterminated regular expression value'));
            }
        // '/' '*' and line-terminators are illegal starts to a regexp:
        } else if (charType > 2) {
            if (charType > 4) {
                throw new ScanException(errorToken(lex, cur - index, ERR_REGEXP_BROKEN,
                    'illegal line-break in regular expression value'));
            // '/' and '*' are illegal start chars for a regexp, though in reality this code is unreachable because we will have scanned them 
            // as a comment already:
            } else {
                String errLexeme = lex.stream.substring(index, Math.min(cur, lex.streamLen));
                throw new ScanException(errorToken(lex, cur - index, ERR_REGEXP_ILLEGAL_START,
                    'regular expression value cannot start with the illegal sequence "' + errLexeme + '"'));
            }
        }
        
        // scan the regexp body (after lead char or lead escape-sequence)
        do {
            charType = RegexpCharsLookup.indexOf(streamArray[cur++]);
            if (charType < 0) {
                continue;
            // escape sequence:
            } else if (charType == 0) {
                // look at the next char after the backslash; accept anything other than line-terminators or EOF:
                charType = RegexpCharsLookup.indexOf(streamArray[cur++]);
                if (charType < 4 || charType == 4 && cur < lex.streamLen) {
                    continue;
                // else, we backtrack so that the next iteration can choke on the illegal line-terminator or EOF:
                } else {
                    cur--;
                }
            // a '[' increments the nested char-class count:
            } else if (charType == 1) {
                state++;
            // a ']' decrements the nested char-class count iff we're currently in a char-class:
            } else if (charType == 2) {
                if (state > 0) {
                    state--;
                }
            // '/' terminates only if we're not in a char-class
            } else if (charType == 3) {
                if (state < 1) {
                    break;
                }
            // \0 is a potential EOF
            } else if (charType == 4) {
                if (cur >= lex.streamLen) {
                    throw new ScanException(errorToken(lex, cur - index, ERR_REGEXP_UNTERM,
                        'unterminated regular expression value'));
                }
            // else, must be > 4, hence an illegal line-terminator:
            } else {
                throw new ScanException(errorToken(lex, cur - index, ERR_REGEXP_BROKEN,
                    'illegal line-break in regular expression value'));
            }
        } while (true);
        
        // scan the optional regexp flags:
        Integer flagsStart = cur;
        String flags = '';
        String ch;
        Boolean dupeFlag = false;
        // we only allow 'imdsux' flags (case-insensitive), and each flag is allowed only once
        while((ch = streamArray[cur]).containsAny('imdsuxIMDSUX') && (cur == flagsStart || !(dupeFlag = ch.containsAny(flags)))) {
            flags += ch;
            cur++;
        }
        if (dupeFlag) {
            throw new ScanException(errorToken(lex, cur + 1 - index, ERR_REGEXP_FLAGS,
                'regular expression value is terminated with duplicate flag "' + ch + '"'));
        } else if (ch.isAlpha()) {
            throw new ScanException(errorToken(lex, cur + 1 - index, ERR_REGEXP_FLAGS,
                'regular expression value is terminated with invalid flag "' + ch + '"; supported flags are "imdsux"'));
        }

        // inline token construction:
        Token cursor = lex.cursor;
        cursor.ttype = REGEXP_LIT;
        Token tok = cursor.clone();
        // lexeme contains the full regexp with enclosing slashes, unprocessed escapes, and suffix flags:
        tok.lexeme = lex.stream.substring(index, cur);
        // value contains the regexp with stripped slashes, unprocessed escapes (escapes will be processed by the System.Pattern engine), and 
        // stripped flags:
        tok.value = lex.stream.substring(index + 1, flagsStart - 1);
        cursor.index = cur;
        cursor.col += cur - index;
        if (cur > flagsStart) {
            tok.regexpFlags = flags;
        }
        return tok;
    }

    public static String serializeToken(Integer ttype) {
        if (ttype == STRING_LIT) {
            return 'string literal';
        } else if (ttype == HEXADEC_LIT) {
            return 'hex number';
        } else if (ttype == DECIMAL_LIT) {
            return 'decimal number';
        } else if (ttype == IDENTIFIER) {
            return 'identifier';
        } else if (ttype >= KEYWORD_MINIMUM && ttype < RESERVED_WORD_MINIMUM) {
            if (ttype == KW_NULL) {
                return '\'null\'';
            } else if (ttype == KW_FALSE) {
                return '\'false\'';
            } else if (ttype == KW_TRUE) {
                return '\'true\'';
            } else {
                // TODO:
                return 'keyword';
//                return 'keyword \'' + ttype.name().toLowerCase().replaceAll('^kw_', '') + '\'';
            }
        } else if (ttype >= RESERVED_WORD_MINIMUM) {
            // TODO:
            return 'reserved word';
//            return 'reserved-word \'' + ttype.name().toLowerCase().replaceAll('^rw_', '') + '\'';
        } else if (ttype == REGEXP_LIT) {
            return 'regular expression';
        } else if (ttype == EOF) {
            return 'end of file';
        } else {
            // TODO:
            return '<ttype ' + ttype + '>';
//            return ttype.name().toLowerCase();
        }
    }
    
    public static String serializeToken(Token tok) {
        if (tok.ttype == STRING_LIT) {
            return 'string literal \'' + tok.lexeme + '\'';
        } else if (tok.ttype == HEXADEC_LIT) {
            return 'hex number \'0x' + tok.lexeme + '\'';
        } else if (tok.ttype == DECIMAL_LIT) {
            return 'decimal number \'' + tok.lexeme + '\'';
        } else if (tok.ttype == IDENTIFIER) {
            return 'identifier \'' + tok.lexeme + '\'';
        } else if (tok.ttype >= KEYWORD_MINIMUM && tok.ttype < RESERVED_WORD_MINIMUM) {
            if (tok.ttype == KW_NULL) {
                return '\'null\'';
            } else if (tok.ttype == KW_FALSE) {
                return '\'false\'';
            } else if (tok.ttype == KW_TRUE) {
                return '\'true\'';
            } else {
                return 'keyword \'' + tok.lexeme + '\'';
            }
        } else if (tok.ttype >= RESERVED_WORD_MINIMUM) {
            return 'reserved word \'' + tok.lexeme + '\'';
        } else if (tok.ttype == REGEXP_LIT) {
            return 'regular expression /' + tok.lexeme + '/';
        } else if (tok.ttype == EOF) {
            return 'end-of-file';
        } else {
            return '\'' + tok.lexeme + '\'';
        }
    }
    
    // creates a new token to the given specifications, and advances this cursor's index/line/col according to that token's metrics;
    // also automatically converts qualifying identifiers into keywords
    // !! processed lexeme may not be null; if lineCount is non-null and > 0 then nextCol cannot be null
    static Token newToken(Token cursor, Integer ttype, String rawLexeme, String processedValue, Integer lineCount, Integer nextCol) {
        cursor.ttype = ttype;
        Token tok = cursor.clone();
        tok.lexeme = rawLexeme;
        tok.value = processedValue;
        cursor.index += rawLexeme.length();
        cursor.line += lineCount != null && lineCount > 0 ? lineCount : 0;
        cursor.col = lineCount != null && lineCount > 0 ? nextCol : cursor.col + rawLexeme.length();
        return tok;
    }

    static Token errorToken(Elex lex, String lexeme, Integer errorType, String msg) {
        // we don't clone the cursor here, because there's no going beyond an ERROR token:
        // TODO: is this a valid assumption?
        //Token errLoc = cursor.clone();
        Token err = lex.cursor;
        err.ttype = ERROR;
        err.lexeme = lexeme;
        err.errorType = errorType;
        err.errorMsg = msg;
        err.penTok = lex.top > -1 ? lex.toks[lex.top] : null;
        // don't increment cursor, since we're done lexing once we hit ERROR or EOF:
        return err;
    }

    static Token errorToken(Elex lex, Integer errlexemeLen, Integer errorType, String msg) {
        // we don't clone the cursor here, because there's no going beyond an ERROR token:
        // TODO: is this a valid assumption?
        //Token errLoc = cursor.clone();
        Token err = lex.cursor;
        Integer errStartIndex = err.index;
        err.ttype = ERROR;
        err.lexeme = lex.stream.substring(errStartIndex, Math.min(errStartIndex + errLexemeLen, lex.streamLen));
        err.errorType = errorType;
        err.errorMsg = msg;
        err.penTok = lex.top > -1 ? lex.toks[lex.top] : null;
        // don't increment cursor, since we're done lexing once we hit ERROR or EOF:
        return err;
    }

    static Token errorToken(Token errLoc, String lexeme, Integer errorType, String msg, Token penTok) {
        // we don't clone the cursor here, because there's no going beyond an ERROR token:
        // TODO: is this a valid assumption?
        Token err = errLoc.clone();
        err.ttype = ERROR;
        err.lexeme = lexeme;
        err.errorType = errorType;
        err.errorMsg = msg;
        err.penTok = penTok;
        // don't increment cursor, since we're done lexing once we hit ERROR or EOF:
        return err;
    }

     static Token eofToken(Token cursor, Token penTok) {
        // we don't clone the cursor here, because there's no going beyond an ERROR token:
        Token err = cursor.clone();
        err.ttype = EOF;
        err.lexeme = '<EOF>';
        err.penTok = penTok;
        // don't increment cursor, since we're done lexing once we hit ERROR or EOF:
        return err;
    }
    
    global class Token {
        public Integer ttype;
        // the raw lexeme that was scanned for this token, including all escape sequences exactly as encountered. this property cannot 
        // null for any token type (including EOF, ERROR)
        public String lexeme;
        // the string value resulting after any processing required on the raw lexeme. for example, STRING_LIT tokens support escape 
        // sequences. in that cases, value contains the string that results after processing these escapes and stripping enclosing quotes. 
        // for DECIMAL_LIT, the value strips the extraneous "." in the case of a "0." token. REGEXP_LIT tokens have a value that strips the 
        // enclosing slashes and flag suffixes. the following token types utilize value; simple punctuator/operator tokens do not require 
        // a value besides their raw lexeme (they would always be equivalent):
        //     STRING_LIT, REGEXP_LIT, DECIMAL_LIT, HEXADEC_LIT
        public String value;
        
        public Integer leadLineBreaks;
        public String[] leadComments;
        public Integer index;
        public Integer line;
        public Integer col;
        //public String moduleURI;
        
         // the following only applies to ttype == STRING_LIT:
        public String[] stringLitParts;
        public Integer[] stringLitCodes;

        // the following only applies to ttype == ERROR:
        public Integer errorType;
        public String errorMsg;

        // the following only applies to ttype == ERROR or EOF:
        // the token immediately preceding the ERROR or EOF:
        public Token penTok;

        // the following only applies to ttype == REGEXP_LIT:
        public String regexpFlags;
        
        Token setRegexpFlags(String flags) {
            if (flags == null) {
                this.regexpFlags = '';
            } else { 
                this.regexpFlags = flags;
            }
            return this;
        }
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
    global static Elex newLexer(String moduleURI, String srcCode) {
        Elex lex = ProtoLex.clone();
        lex.stream = srcCode;
        lex.streamArray = srcCode.split('');
        //lex.streamArray.remove(0);
        lex.streamLen = srcCode.length();
        // !! append 4 terminating NULL chars '\0', to allow simpler scanning logic that more gracefully handles tests that hit end-of-file 
        // (e.g. so that we never cause ArrayIndexOutOfBounds by looking ahead 1 char in streamArray) -- note that some of these tests will 
        // accept an actual \0 char (e.g. inside a string literal; inside a comment; inside RegExp), so they must include an additional 
        // streamLen test to disambiguate a true source \0 from an EOF. We use 4 \0 chars to facilitate up to 4 chars of lookahead:
        lex.streamArray.addAll(new String[]{ NullChar, NullChar, NullChar, NullChar });
        
        Token cur = lex.cursor = new Token();
        //cur.moduleURI = moduleURI == null ? '<anonymous>' : moduleURI;
        cur.ttype = EMPTY;
        cur.line = 0;
        cur.col = 0;
        cur.index = 0;
        cur.leadLineBreaks = 0;
        cur.leadComments = null;

        lex.scanAll();
        return lex;
    }
    
    static Elex ProtoLex = new Elex();
}