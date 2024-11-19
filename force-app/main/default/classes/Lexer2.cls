/*
 * Mike Ulveling
 */
global class Lexer2 {
    
    // each token id has an entry in this list; the value is its "expression routing/parsing-level", to be used by the parser. the parse-level is the
    // same as the op's expr level (0-based, e.g. Comma=0; Assign=1). note that all tokens which are not expression-routing infix/postfix operators
    // (e.g. '{') will have an entry value of -1, which dictates that the current expr-part shall be terminated:
    public static final Integer[] ExprLevelTable = new Integer[]{};
    public static final Integer EXPR_TERM = -1;
    
    public static final Integer DIV_CONTEXT = 0;
    public static final Integer REGEXP_CONTEXT = 1;
    
    // and here, each entry is a bitfield that identifies that token's special classifications -- note these classifications are not mututally
    // exclusive:
    // 0   => a token with no special classifications
    // 2^0 => token may serve as a prefix operator (i.e. unary or new op)
    // 2^1 => token is a valid 1st token in an expression-statement
    // 2^2 => token looks like data and thus sets a div context (vs. regexp context)
    // 2^3 => token can serve as a primary expr's data
    // 2^4 => token is acceptable as an object literal's key:
    // 2^5 => token is an ECMAScript5 IdentifierName (identifiers, keywords, reserved words):
    public static final Integer[] TokenClassifications = new Integer[]{};
    // tokens with no special classification:
    public static final Integer TKLASS_NONE = 0;
    // tokens that can represent a unary prefix operator:
    public static final Integer TKLASS_PREFIX = 1;
    // tokens that can serve as the lead-token to an expression-statement:
    public static final Integer TKLASS_EXPR_STMT_LEAD = 1 << 1;
    // tokens that look like "data", and thus a subsequent '/' char should be interpreted as a divide-op rather than a regexp-literal:
    public static final Integer TKLASS_SETS_DIV_CONTEXT = 1 << 2;
    // tokens that can be accepted as a PrimaryExpression data node that can be resolved to a value in the parsing phase (e.g. string literal, regexp,
    // boolean values):
    public static final Integer TKLASS_PRIMARY_DATA = 1 << 3;
    // tokens that can be accepted as an object-literal property key:
    public static final Integer TKLASS_OBJECT_KEY = 1 << 4;
    // tokens that qualify as an ECMAScript5 IdentifierName (identifiers, keywords, reserved words):
    public static final Integer TKLASS_IDENT_NAME = 1 << 5;
    
    public static Integer tokid = 0;
    
    static Integer tokid() {
        return tokid(EXPR_TERM, TKLASS_NONE);
    }
    
    static Integer tokid(Integer exprRoutingLvl, Integer classifications) {
        ExprLevelTable.add(exprRoutingLvl);
        TokenClassifications.add(classifications);
        return tokid++;
    }
    
    // empty token to serve as the "none" prior token before we've scanned our first token:
    public static final Integer EMPTY = tokid();
    // the terminating "end-of-file" token:
    public static final Integer EOF = tokid();
    // the NEEDS_FEEDBACK token can temporarily terminate the token stack until scanMore is called again to provide contextual feedback (i.e. from
    // the parser, which knows the needs of the current grammar production); this token will be replaced by (i.e. will resolve to) a REGEXP, DIVIDE,
    // or ASSIGN_DIVIDE on a subsequent scanMore(). note that this setup has been designed to not interfere with the following mechanisms:
    // 1. ASI - the NEEDS_FEEDBACK token scans and holds lead boundary information as ususal, and this boundary is passed on to its replacement upon 
    //    a subsequent scanMore(). Thus, automatic semicolon insertion is not altered by this temporary substitution. 
    // 2. LL(1) Lookahead - All non-expression grammar contexts will equally reject a REGEXP, DIVIDE, and ASSIGN_DIVIDE token, so substituting in a 
    //    NEEDS_FEEDBACK token for any of them will not change behavior since we equally reject a NEEDS_FEEDBACK token in these scenarios and report
    //    it as a '/' in parse errors. The expr parser knows to look for a NEEDS_FEEDBACK token at the appropriate times for lookahead, and will call
    //    scanMore() with the proper context feedback as necessary.
    // 3. Expression-Statement Prediction - Another case of lookahead; since NEEDS_FEEDBACK may indicate a divide op (which is not a valid start to
    //    any grammar production, and is not used at all at the statement level) or a REGEXP (which is a valid start to an expression or an
    //    expression-statement), we assume that in the context of checking for an expr-statement we should assume REGEXP (otherwise, it's a parse 
    //    error anyways) -- and thus, we set the TKLASS_EXPR_STMT_LEAD classification bit on this token
    // 4. Expression Routing/Termination - Since the expr parser will check for a NEEDS_FEEDBACK token and call scanMore() as necessary to resolve the
    //    token, it doesn't really matter what we set for the expr-level of this token (we use EXPR_TERM==-1 here).
    // !! the lead '/' and its 3 possible resulting tokens represents the only part of the ECMA-262 lexical grammar that cannot be disambiguated
    // without contextual feedback from the parser -- otherwise, the scanner could be completely isolated from the parser
    public static final Integer NEEDS_FEEDBACK = tokid(EXPR_TERM, TKLASS_EXPR_STMT_LEAD);
    // 1-char punctuators:
    public static final Integer COMMA         = tokid(0, TKLASS_NONE);
    public static final Integer COLON         = tokid();
    public static final Integer SEMICOLON     = tokid();
    public static final Integer DOT           = tokid(15, TKLASS_NONE); // Expr.Call
    public static final Integer OPEN_BRACE    = tokid();
    // !! '}' cannot automatically set a div context in the scanner, because it may be the end of an object-literal (data; sets div context) or a
    // statement block (sets regexp context); when we encounter a non-comment '/' char following a '}', then we'll require parser feedback in order
    // to set the correct context (i.e. the '/' in that case generates a NEEDS_FEEDBACK token until we receive parser feedback to resolve it):
    public static final Integer CLOSE_BRACE   = tokid(EXPR_TERM, TKLASS_NONE);
    public static final Integer OPEN_BRACKET  = tokid(15, TKLASS_EXPR_STMT_LEAD); // Expr.Call
    public static final Integer CLOSE_BRACKET = tokid(EXPR_TERM, TKLASS_SETS_DIV_CONTEXT);
    public static final Integer OPEN_PAREN    = tokid(15, TKLASS_EXPR_STMT_LEAD); // Expr.Call
    public static final Integer CLOSE_PAREN   = tokid(EXPR_TERM, TKLASS_SETS_DIV_CONTEXT);

    // expression-level operators & keywords:
    public static final Integer ASSIGNMENT          = tokid(1, TKLASS_NONE);
    // !! note that the ordering of these compound assign ops matters. generally they must follow the binary op precedence, and also the URIGHT_SHIFT
    // must follow after LEFT_SHIFT and RIGHT_SHIFT:
    public static final Integer ASSIGN_BIT_OR       = tokid(1, TKLASS_NONE);
    public static final Integer ASSIGN_BIT_XOR      = tokid(1, TKLASS_NONE);
    public static final Integer ASSIGN_BIT_AND      = tokid(1, TKLASS_NONE);
    public static final Integer ASSIGN_LEFT_SHIFT   = tokid(1, TKLASS_NONE);
    public static final Integer ASSIGN_RIGHT_SHIFT  = tokid(1, TKLASS_NONE);
    public static final Integer ASSIGN_URIGHT_SHIFT = tokid(1, TKLASS_NONE);
    public static final Integer ASSIGN_PLUS         = tokid(1, TKLASS_NONE);
    public static final Integer ASSIGN_MINUS        = tokid(1, TKLASS_NONE);
    public static final Integer ASSIGN_MULTIPLY     = tokid(1, TKLASS_NONE);
    public static final Integer ASSIGN_DIVIDE       = tokid(1, TKLASS_NONE);
    // !! ASSIGN_MODULUS must have the largest id value amongst MINUS/DIVIDE/MODULUS, because Instruc.CompoundAssignTable's allocation depends on it:
    public static final Integer ASSIGN_MODULUS      = tokid(1, TKLASS_NONE);
    
    public static final Integer CONDITIONAL         = tokid(2, TKLASS_NONE);
    public static final Integer LOGICAL_OR          = tokid(3, TKLASS_NONE);
    public static final Integer LOGICAL_AND         = tokid(4, TKLASS_NONE);
    public static final Integer BIT_OR              = tokid(5, TKLASS_NONE);
    public static final Integer BIT_XOR             = tokid(6, TKLASS_NONE);
    public static final Integer BIT_AND             = tokid(7, TKLASS_NONE);
    public static final Integer EQUALS              = tokid(8, TKLASS_NONE);
    public static final Integer NOT_EQUALS          = tokid(8, TKLASS_NONE);
    public static final Integer STRICT_EQUALS       = tokid(8, TKLASS_NONE);
    public static final Integer STRICT_NOT_EQUALS   = tokid(8, TKLASS_NONE);
    public static final Integer GREATER_THAN        = tokid(9, TKLASS_NONE);
    public static final Integer GREATER_THAN_EQUALS = tokid(9, TKLASS_NONE);
    public static final Integer LESS_THAN           = tokid(9, TKLASS_NONE);
    public static final Integer LESS_THAN_EQUALS    = tokid(9, TKLASS_NONE);
    public static final Integer LEFT_SHIFT          = tokid(10, TKLASS_NONE);
    public static final Integer RIGHT_SHIFT         = tokid(10, TKLASS_NONE);
    public static final Integer URIGHT_SHIFT        = tokid(10, TKLASS_NONE);
    public static final Integer PLUS                = tokid(11, TKLASS_EXPR_STMT_LEAD | TKLASS_PREFIX);
    public static final Integer MINUS               = tokid(11, TKLASS_EXPR_STMT_LEAD | TKLASS_PREFIX); // 43
    public static final Integer MULTIPLY            = tokid(12, TKLASS_NONE);
    public static final Integer DIVIDE              = tokid(12, TKLASS_NONE);
    public static final Integer MODULUS             = tokid(12, TKLASS_NONE);
    public static final Integer LOGICAL_NOT         = tokid(EXPR_TERM, TKLASS_EXPR_STMT_LEAD | TKLASS_PREFIX);  // unary op; special handling
    public static final Integer BIT_NOT             = tokid(EXPR_TERM, TKLASS_EXPR_STMT_LEAD | TKLASS_PREFIX); // unary op; special handling
    // !! note: '++' and '--' are super-ambiguous because they can be prefix (in which case we'd want regexp context) or postfix 
    // (in which case we'd want div context), and it's very difficult to differentiate the two in a lexical analyzer. here we don't 
    // attempt to differentiate; we choose to support the postfix cases (i.e. treat them like data) because a postfix+division is much 
    // more important (and likely) than a prefix+regexp-literal (which would result in a ReferenceError being thrown anyways):
    public static final Integer INCREMENT           = tokid(14, TKLASS_EXPR_STMT_LEAD | TKLASS_PREFIX); // postfix
    public static final Integer DECREMENT           = tokid(14, TKLASS_EXPR_STMT_LEAD | TKLASS_PREFIX); // postfix
    
    // complex tokens:
    public static final Integer IDENTIFIER = tokid(EXPR_TERM, ((TKLASS_EXPR_STMT_LEAD | TKLASS_SETS_DIV_CONTEXT) | TKLASS_OBJECT_KEY) | TKLASS_IDENT_NAME);
    // the ECMAScript5 IdentifierNames "eval" and "arguments" are restricted from usage as ECMAScript5 Identifier when in strict mode -- hence I've
    // separated them out into their own token type in order to allow the parser to better make this distinction and provide a more lucid error
    // messages for their incorrect usage in strict mode. non-strict mode should treat this token as an IDENTIFIER:
    public static final Integer IDENT_NAME_EVAL_OR_ARGUMENTS = tokid(EXPR_TERM, ((TKLASS_EXPR_STMT_LEAD | TKLASS_SETS_DIV_CONTEXT) | TKLASS_OBJECT_KEY) | TKLASS_IDENT_NAME);
    public static final Integer HEX_NUMBER     = tokid(EXPR_TERM, ((TKLASS_EXPR_STMT_LEAD | TKLASS_SETS_DIV_CONTEXT) | TKLASS_OBJECT_KEY) | TKLASS_PRIMARY_DATA);
    public static final Integer DECIMAL_NUMBER = tokid(EXPR_TERM, ((TKLASS_EXPR_STMT_LEAD | TKLASS_SETS_DIV_CONTEXT) | TKLASS_OBJECT_KEY) | TKLASS_PRIMARY_DATA);
    public static final Integer STRING_LITERAL = tokid(EXPR_TERM, ((TKLASS_EXPR_STMT_LEAD | TKLASS_SETS_DIV_CONTEXT) | TKLASS_OBJECT_KEY) | TKLASS_PRIMARY_DATA);
    public static final Integer REGEXP         = tokid(EXPR_TERM, (TKLASS_EXPR_STMT_LEAD | TKLASS_SETS_DIV_CONTEXT) | TKLASS_PRIMARY_DATA);
    
    // keywords, followed by future reserved words:
    public static final Integer KEYWORD_MINIMUM = tokid; // all keywords are >= this id
    public static final Integer KW_IN           = tokid(9, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_INSTANCEOF   = tokid(9, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_TYPEOF       = tokid(EXPR_TERM, ((TKLASS_EXPR_STMT_LEAD | TKLASS_PREFIX) | TKLASS_OBJECT_KEY) | TKLASS_IDENT_NAME); // unary op
    public static final Integer KW_DELETE       = tokid(EXPR_TERM, ((TKLASS_EXPR_STMT_LEAD | TKLASS_PREFIX) | TKLASS_OBJECT_KEY) | TKLASS_IDENT_NAME); // unary op
    public static final Integer KW_VOID         = tokid(EXPR_TERM, ((TKLASS_EXPR_STMT_LEAD | TKLASS_PREFIX) | TKLASS_OBJECT_KEY) | TKLASS_IDENT_NAME); // unary op
    public static final Integer KW_NEW          = tokid(EXPR_TERM, ((TKLASS_EXPR_STMT_LEAD | TKLASS_PREFIX) | TKLASS_OBJECT_KEY) | TKLASS_IDENT_NAME); // new op
    public static final Integer KW_TRUE         = tokid(EXPR_TERM, (((TKLASS_EXPR_STMT_LEAD | TKLASS_SETS_DIV_CONTEXT) | TKLASS_OBJECT_KEY) | TKLASS_PRIMARY_DATA) | TKLASS_IDENT_NAME);
    public static final Integer KW_FALSE        = tokid(EXPR_TERM, (((TKLASS_EXPR_STMT_LEAD | TKLASS_SETS_DIV_CONTEXT) | TKLASS_OBJECT_KEY) | TKLASS_PRIMARY_DATA) | TKLASS_IDENT_NAME);
    public static final Integer KW_NULL         = tokid(EXPR_TERM, (((TKLASS_EXPR_STMT_LEAD | TKLASS_SETS_DIV_CONTEXT) | TKLASS_OBJECT_KEY) | TKLASS_PRIMARY_DATA) | TKLASS_IDENT_NAME);
    
    public static final Integer KW_THIS     = tokid(EXPR_TERM, ((TKLASS_EXPR_STMT_LEAD | TKLASS_SETS_DIV_CONTEXT) | TKLASS_OBJECT_KEY) | TKLASS_IDENT_NAME);
    public static final Integer KW_VAR      = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_FUNCTION = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_WHILE    = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_DO       = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_FOR      = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_SWITCH   = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_CASE     = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_DEFAULT  = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_IF       = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_ELSE     = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_THROW    = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_RETURN   = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_BREAK    = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_CONTINUE = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_TRY      = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_CATCH    = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_FINALLY  = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_DEBUGGER = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer KW_WITH     = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    // future reserved words:
    public static final Integer RESERVED_WORD_MINIMUM = tokid; // all reserved words (including strict mode reserved) are >= this id
    public static final Integer RW_CLASS    = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer RW_ENUM     = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer RW_EXTENDS  = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer RW_SUPER    = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer RW_CONST    = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer RW_EXPORT   = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer RW_IMPORT   = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    // ECMAScript5 strict mode future reserved words:
    public static final Integer STRICT_RESERVED_MINIMUM = tokid; // all strict-mode reserved words are >= this id
    public static final Integer SRW_IMPLEMENTS = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer SRW_LET        = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer SRW_PRIVATE    = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer SRW_PUBLIC     = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer SRW_YIELD      = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer SRW_INTERFACE  = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer SRW_PACKAGE    = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer SRW_PROTECTED  = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    public static final Integer SRW_STATIC     = tokid(EXPR_TERM, TKLASS_OBJECT_KEY | TKLASS_IDENT_NAME);
    
    // transition states:
    
    // the "transition-state" bit is the 2^8 bit (256); the 7 bits below this can enumerate up to 255 different token types:
    static final Integer TS_BIT = 1 << 8;
    // use this mask with '&' to remove the lower token-type bits, thus revealing the transition-state:
    static final Integer TS_MASK = ~0 << 8;
    // use this mask with '&' to remove the upper transition-state bits, thus revealing the token-type (if any):
    static final Integer TOKEN_MASK = ~TS_MASK;
    
    static Integer tsid = 1;
    // signals that we need to parse a complex token of the type specified in the lower bits (e.g. IDENTIFIER):
    static final Integer TS_COMPLEX = tsid++ << 8;
    // signals that we need to try a 2-char lookup, and if that fails we can fallback to the token-type specified 
    // in the lower bits:
    static final Integer TS_NEXT = tsid++ << 8;
    // signals that we got a leading 0; further lookahead is required to distinguish between DECIMAL_NUMBER and HEX_NUMBER:
    static final Integer TS_LEAD_ZERO = tsid++ << 8;
    // we use special transition-states for strings, instead of (TS_COMPLEX | STRING_LITERAL), so that we can differentiate 
    // between the SQ and DQ flavors:
    static final Integer TS_SQ_STRING = tsid++ << 8;
    static final Integer TS_DQ_STRING = tsid++ << 8;
    
    // the following transition-states differentiate between decimal numbers that required 2 chars of lookahead; these will
    // be either a 0[0-9] (starting-state 0) or a \.[0-9] (starting-state 1):
    static final Integer TS_DECIMAL_STATE0 = tsid++ << 8;
    static final Integer TS_DECIMAL_STATE1 = tsid++ << 8;

    // using a hash map here would look more elegant, but the following scheme is far more performant (in Apex, indexOf is much faster than a Map
    // lookup, at least until the search string becomes extremely long
    // !! note that entries for letters and digits are generated and added in the following static block
    // !! I've removed the backslash char from this index, because identifiers that start with a unicode esc sequence (and identifiers are the only
    // tokens which can legally start with a backslash) need to fallthrough to more rigorous processing:
    static String TransStateLookup1 = ',:;{}[]()?~\'"$_!=><+-*%&|^.0';
    // resolves 1 char of lookahead to a concrete token type, a transition-state, or null (i.e. not a legal "black" token):
    static final Integer[] TransStateTable1 = new Integer[]{
        COMMA,
        COLON,
        SEMICOLON,
        OPEN_BRACE,
        CLOSE_BRACE,
        OPEN_BRACKET,
        CLOSE_BRACKET,
        OPEN_PAREN,
        CLOSE_PAREN,
        CONDITIONAL,
        BIT_NOT,
        TS_SQ_STRING,
        TS_DQ_STRING,
        TS_COMPLEX | IDENTIFIER,
        TS_COMPLEX | IDENTIFIER,
        TS_NEXT | LOGICAL_NOT,
        TS_NEXT | ASSIGNMENT,
        TS_NEXT | GREATER_THAN,
        TS_NEXT | LESS_THAN,
        TS_NEXT | PLUS,
        TS_NEXT | MINUS,
        TS_NEXT | MULTIPLY,
        TS_NEXT | MODULUS,
        TS_NEXT | BIT_AND,
        TS_NEXT | BIT_OR,
        TS_NEXT | BIT_XOR,
        TS_NEXT | DOT,
        TS_LEAD_ZERO
    };
    // add transition-states for the usual ASCII digits [0-9] and letters [a-zA-Z]:
    static {
        for (Integer i=1; i <=9; i++) {
            TransStateLookup1 += i;
            TransStateTable1.add(TS_COMPLEX | DECIMAL_NUMBER);
        }
        String alpha = 'abcdefghijklmnopqrstuvwxyz';
        String ch;
        for (Integer i=0; i < alpha.length(); i++) {
            TransStateLookup1 += (ch = alpha.mid(i, 1));
            TransStateTable1.add(TS_COMPLEX | IDENTIFIER);
            TransStateLookup1 += (ch = ch.toUpperCase());
            TransStateTable1.add(TS_COMPLEX | IDENTIFIER);
        }
    }
    // concats the most common whitespace chars and then the backslash with TransStateLookup1, so that the simple-boundary scanner loop can collect
    // as much information as possible in just 1 indexOf call plus 1 array-access.
    // !! note that this adds in the backslash char at index=3 -- otherwise we wouldn't recognize it as a common end-of-boundary, and thus would
    // invoke an expensive boundary matcher on identifiers that start with a unicode esc-sequence.
    static final String WhiteBlackLookup = ' \t\n\\' + TransStateLookup1;
    // common identifier terminators: start with TransStateLookup1, add in the [ \t\r] chars, remove the alphanumeric chars, add a forward-slash, the
    // null \0 char, and unicode line-breaks:
    static final String IdentTerminatorsLookup = ' \t\n,:;{}[]()?~\'"$_!=><+-*%&|^./\r' + String.fromCharArray(new Integer[]{ 0, 2028, 2029 });
    
    // resolves 2 chars of lookahead to a concrete token type, a transition-state, or null (i.e. fallback to the token type carried by 
    // the lower-bits of the prior result from tsMap1):
    static String TransStateLookup2 = '==!=++--&&||>=<=*=%=+=-=|=^=&=<<>>0x0X';
    static final Integer[] TransStateTable2 = new Integer[]{
        TS_NEXT | EQUALS, null,
        TS_NEXT | NOT_EQUALS, null,
        INCREMENT, null,
        DECREMENT, null,
        LOGICAL_AND, null,
        LOGICAL_OR, null,
        GREATER_THAN_EQUALS, null,
        LESS_THAN_EQUALS, null,
        ASSIGN_MULTIPLY, null,
        ASSIGN_MODULUS, null,
        ASSIGN_PLUS, null,
        ASSIGN_MINUS, null,
        ASSIGN_BIT_OR, null,
        ASSIGN_BIT_XOR, null,
        ASSIGN_BIT_AND, null,
        TS_NEXT | LEFT_SHIFT, null,
        TS_NEXT | RIGHT_SHIFT, null,
        TS_COMPLEX | HEX_NUMBER, null,
        TS_COMPLEX | HEX_NUMBER, null
    };
    // add transition states for \.\d (e.g. '.9') and 0\d (e.g. '09'):
    static {
        for (Integer i=0; i <=9; i++) {
            TransStateLookup2 += '.' + i;
            TransStateTable2.add(TS_DECIMAL_STATE1 | DECIMAL_NUMBER);
            TransStateTable2.add(null);
            // since a ch1=='0' is deferred to tsMap2, we must also account for all (min 2-char) decimal numbers with a leading 0:
            TransStateLookup2 += '0' + i;
            TransStateTable2.add(TS_DECIMAL_STATE0 | DECIMAL_NUMBER);
            TransStateTable2.add(null);
        }
    }
    
    // resolves 3 chars of lookahead to a concrete token type, a transition-state, or null (i.e. fallback to the token type carried by 
    // the lower-bits of the prior result from tsMap2):
    static final String TransStateLookup3 = '===!==<<=>>=>>>';
    static final Integer[] TransStateTable3 = new Integer[]{
        STRICT_EQUALS, null, null,
        STRICT_NOT_EQUALS, null, null,
        ASSIGN_LEFT_SHIFT, null, null,
        ASSIGN_RIGHT_SHIFT, null, null,
        TS_NEXT | URIGHT_SHIFT, null, null
    };
    
    static final Map<String, Integer> KeywordsMap = new Map<String, Integer>{
        // "eval" and "arguments" are not reserved words nor keywords, but they are restricted from usage as Identifiers when in strict mode:
        'eval'       => IDENT_NAME_EVAL_OR_ARGUMENTS,
        'arguments'  => IDENT_NAME_EVAL_OR_ARGUMENTS,
        // each of the following is either a keyword, a reserved word, or a strict mode reserved word:
        'this'       => KW_THIS,
        'var'        => KW_VAR,
        'function'   => KW_FUNCTION,
        'while'      => KW_WHILE,
        'do'         => KW_DO,
        'for'        => KW_FOR,
        'switch'     => KW_SWITCH,
        'case'       => KW_CASE,
        'default'    => KW_DEFAULT,
        'in'         => KW_IN,
        'instanceof' => KW_INSTANCEOF,
        'if'         => KW_IF,
        'else'       => KW_ELSE,
        'return'     => KW_RETURN,
        'break'      => KW_BREAK,
        'continue'   => KW_CONTINUE,
        'delete'     => KW_DELETE,
        'void'       => KW_VOID,
        'throw'      => KW_THROW,
        'try'        => KW_TRY,
        'catch'      => KW_CATCH,
        'finally'    => KW_FINALLY,
        'typeof'     => KW_TYPEOF,
        'new'        => KW_NEW,
        'true'       => KW_TRUE,
        'false'      => KW_FALSE,
        'null'       => KW_NULL,
        'debugger'   => KW_DEBUGGER,
        'with'       => KW_WITH,
        'class'      => RW_CLASS,
        'enum'       => RW_ENUM,
        'extends'    => RW_EXTENDS,
        'super'      => RW_SUPER,
        'const'      => RW_CONST,
        'export'     => RW_EXPORT,
        'import'     => RW_IMPORT,
        // the following are ECMAScript5 strict mode reserved words:
        'implements' => SRW_IMPLEMENTS,
        'let'        => SRW_LET,
        'private'    => SRW_PRIVATE,
        'public'     => SRW_PUBLIC,
        'yield'      => SRW_YIELD,
        'interface'  => SRW_INTERFACE,
        'package'    => SRW_PACKAGE,
        'protected'  => SRW_PROTECTED,
        'static'     => SRW_STATIC
    };
    
    // !! note that the parser can identify strict-mode reserved tokens by the test: token.ttype >= STRICT_RESERVED_MINIMUM:
    static String KeywordsLookup = '';
    static Integer[] KeywordsTable;
    static Integer[] KeywordLenTable;
    static {
        String keywordsList = 'if in do for var try new true false else this null with enum case while throw catch function switch default instanceof return break continue delete eval arguments class finally typeof void debugger extends super const export import'
                // and here are the strict-mode reserved words:
                + 'implements let private public yield interface package protected static';
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

    // in addition to unicode letters and unicode escape sequences, an identifier may start in a [$_]:
    static final String AdditionalIdentStartChars = '$_';
    // in addition to the unicode alphanumeric chars and [$_], we add the zero-width joiner (\u200D <ZWJ>) and non-joiner (\u200C <ZWNJ>) chars to
    // our "common" identifier parts:
    static final String AdditionalIdentPartChars = '$_' + String.fromCharArray(new Integer[]{ 8204, 8205 });
    
    // rigorous (but slow) patterns that allow adherence to the ECMA-262 spec regarding unicode chars in identifiers:
    static final String IdentifierStartCharClass = '[$_\\p{L}\\p{Nl}]';
    static final String IdentifierPartCharClass = '[$_\\p{L}\\p{Nl}\\p{Nd}\\u200C\\u200D\\p{Pc}\\p{Mc}\\p{Mn}]';
    // used for identifier validation in "tricky" cases only, after unicode escape sequences have been processed:
    static final Pattern ValidUnescapedIdentifierWholePatt = Pattern.compile(IdentifierStartCharClass + IdentifierPartCharClass + '*+');
    // this does not include an identifier start-char:
    static final Pattern ValidUnescapedIdentifierPartPatt = Pattern.compile(IdentifierPartCharClass + '++');
    static final Pattern IdentStartWithNefariousCharsPatt = Pattern.compile('^' + IdentifierStartCharClass + IdentifierPartCharClass + '*+');
    // matches as many '$', '_', unicode-letters/unicode-digits/<ZWJ>/<ZWNJ>/connector-punctuation/non-spacing-marks/combining-marks as it finds:
    static final Pattern IdentPartWithNefariousCharsPatt = Pattern.compile('^' + IdentifierPartCharClass + '++');
    
    static final String UnicodeSpecialLineTerminators = String.fromCharArray(new Integer[]{ 2028, 2029 });
    static final String NormalModeBreakingCharsSQ = '\'\n\r\\' + UnicodeSpecialLineTerminators;
    static final String NormalModeBreakingCharsDQ = '"\n\r\\' + UnicodeSpecialLineTerminators;
    static final String DivChar = '/';
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
    // following a '++' or '--') will result in a "NEEDS_FEEDBACK" token to prompt the parser for contentual feedback and
    // a subsequent scanMore() call:
    Token cursor;
    
    // the starting token-stack size (i.e. lmt + 1) is 20; this will double as necessary:
    public Token[] toks = new Token[20];
    public Integer lmt = -1;
    Integer top = -1;
    public Integer next = 0;
    
    // there should only be 1 instance of <EOF> per stream; we set it here when first encountered and then immediately return it thereafter for 
    // all subsequent scanToken calls:
    Token termEOF;
    
    Matcher identStartWithNefariousCharsMatcher;
    Matcher identPartWithNefariousCharsMatcher;
    
    // scans all tokens from the source code into the tokens-stack, until we hit a terminating EOF or a NEEDS_FEEDBACK:
    public void scanMore(Integer contextualFeedback) {
        // the passed-in contextualFeedback is only good for the first token; we track this by storing the current top-of-stack index:
        Integer contextualFeedbackTop = top;
        String[] streamArray = this.streamArray;
        Integer streamLen = this.streamLen;
        String stream = this.stream;
        Token cursor = this.cursor;
        try {
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
                    // !! this loop is guaranteed not to iterate; it is used instead of a plain code-block because Apex (unlike beautiful,
                    // wonderous ECMAScript) does not have facilities to allow break statements to target a code-block:
                    do {
                        // the following while loop attempts to scan consecutive 'simple' whitespace chars; this scenario should be by far more common
                        // than any other non-null boundary; if the boundary is not simple then we'll fallthrough to leverage a more robust (but
                        // slower) scaner. simple whitespace includes the space [ ], tab \t, and newline \n chars -- but not Microsoft's goddamned 
                        // \r\n, and not the specical unicode chars:
                        Integer wbIndex;
                        Integer colStart = index;
                        
                        // common whitespace chars occupy the first 3 positions of WhiteBlackLookup; next is the backslash char, and after that is all 
                        // the common black-token start chars -- thus, when we encounter a common "black" char, we can get its 1st transition-state 
                        // index by simply subtracting 4 (backslash must fallthrough to more rigorous processing):
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
                            // !! note that if wbIndex - 4 == -1, then that means we encountered the backslash char (which is definitely a boundary 
                            // terminator, but represents the start of a "difficult" identifier); if > -1 then we got an unambiguous 'black' char that 
                            // can be easily identified; if < -1 then it is something more difficult to reckon with:
                            if ((tsIndex1 = wbIndex - 4) > -2) {
                                ch1 = streamArray[index];
                                break;
                            }
                        
                        // else, we didn't parse a simple boundary part; if we're looking at the start of a token that is unambiguously a "black" 
                        // token, then we have no leading boundary and we can proceed with scanning the black token.
                        // !! note that our result tsIndex1 will be re-used in the subsequent black-token scanning logic, to save a hash lookup:
                        // !! note that if wbIndex - 4 == -1, then that means we encountered the backslash char (which is definitely a boundary 
                        // terminator, but represents the start of a "difficult" identifier); if > -1 then we got an unambiguous 'black' char that
                        // can be simply mapped; if < -1 then it is something difficult:
                        } else if ((tsIndex1 = wbIndex - 4) > -2) {
                            hasLead = false;
                            ch1 = streamArray[index];
                            break;
                        }
                        
                        // else, we didn't parse a simple boundary and we couldn't easily determine whether we're looking at an uncommon black token 
                        // start or a complex boundary part; we must run through more rigorous (and slower) scanning logic: 
                        Integer boundaryType;
                        while ((boundaryType = ComplexBoundaryLookup.indexOf(streamArray[index])) > -1) {
                            // a forward-slash:
                            if (boundaryType == 0) {
                                Integer commentType = CommentTypeLookup.indexOf(streamArray[index + 1]);
                                // if the '/' does not begin a comment, then it must indicate a black-token; break out of this loop (and subsequently,
                                // the main boundary loop):
                                if (commentType < 0)
                                    break;
                                // multi-line comment:
                                else if (commentType == 0) {
                                    // mark the start of the comment:
                                    Integer commentStart = index;
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
                                            if (commentCharType == 2 && '\n'.equals(streamArray[index + 1]))
                                                index += 2;
                                            else
                                                index++;
                                            
                                            colStart = index;
                                        // when encountering a '*' char, we must check for a subsequent '/'
                                        } else if (commentCharType == 1) {
                                            // '*' followed by a '/' - we've found the end of the comment:
                                            if ('/'.equals(streamArray[index + 1])) {
                                                index += 2;
                                                String commentText = stream.substring(commentStart, index);
                                                if (cursor.leadComments == null)
                                                    cursor.leadComments = new String[]{ commentText };
                                                else 
                                                    cursor.leadComments.add(commentText);
                                                
                                                break;
                                            // else it was just a plain '*' char; continue scanning the comment:
                                            } else {
                                                index++;
                                            }
                                        // if we're looking at a \0, then check for a possible EOF:
                                        } else {
                                            if (index >= streamLen)
                                                throw new ScanException(0, 'unterminated multi-line comment');
                                            
                                            index++;
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
                                            if (cursor.leadComments == null)
                                                cursor.leadComments = new String[]{ commentText };
                                            else 
                                                cursor.leadComments.add(commentText);
                                            
                                            break;
                                        // if we're looking at a \0, then check for a possible EOF:
                                        } else {
                                            // verify we haven't hit EOF:
                                            if (index < streamLen) {
                                                index++;
                                            } else 
                                                break;
                                        }
                                    } while (true);
                                    cursor.col += index - commentStart;
                                }

                            // a line-terminator:
                            } else if (boundaryType < 5) {
                                cursor.col = 0;
                                cursor.leadLineBreaks++;
                                // try to identify a \r\n sequence:
                                if (boundaryType == 8 && '\n'.equals(streamArray[index + 1]))
                                    index += 2;
                                else 
                                    index++;
                                
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
                        toks[++top] = termEOF == null ? (termEOF = termEOF(cursor)) : termEOF;
                        continue;
                    }

                    // !! note that due to the streamlined logic, we are guaranteed to have the current tsIndex1 already set from the above logic;
                    // if tsIndex1 is > -1, then ch1 must have matched either an unambiguous 1-char black token or a transition-state:
                    if (tsIndex1 > -1) {
                        Integer tsRes1 = TransStateTable1[tsIndex1];
                        // if we've unambiguously matched a 1-char operator token, then create and return it immediately:
                        if (tsRes1 < TS_BIT) {
                            // construct the new token inline, to save a call:
                            cursor.ttype = tsRes1;
                            Token tok = cursor.clone();
                            cursor.index += 1;
                            cursor.col += 1;
                            tok.lexeme = ch1;
                            toks[++top] = tok;
                            continue;
                            
                        // else, if we've unambiguously resolved to a complex token, then scan it:
                        } else if ((tsRes1 & TS_MASK) == TS_COMPLEX) {
                            Integer ttype;
                            if ((ttype = tsRes1 & TOKEN_MASK) == IDENTIFIER) {
                                // see ECMA-262 7.8.3:
                                if (!hasLead && (cursor.ttype == HEX_NUMBER || cursor.ttype == DECIMAL_NUMBER))
                                    throw new ScanException(0, 'identifier cannot follow number without a separating boundary');
                                
                                // we start by assuming that we probably have a "simple" identifier (no unicode combining-marks, connector 
                                // punctuation, or unicode escapes), and attempt to scan it as such. we already know the 1st char is in the set
                                // [$_a-zA-Z], since we got we got a tsRes1 and these are the only identifier start-chars in tsIndex1. thus, we
                                // immediately advance past it the start char, then scan past every other "simple" identifier char that we encounter:
                                Integer cur = index + 1;
                                // note that isAlphanumeric does indeed identify extended unicode letters and digits:
                                while (streamArray[cur].isAlphanumeric() || AdditionalIdentPartChars.contains(streamArray[cur]))
                                    cur++;
                                
                                // if the next char is a common white or black start char, then we know that is represents the end of this identifier 
                                // token, because otherwise the above loop would have scanned past it. if we don't recognize the char as a common 
                                // identifier terminating char, then we must continue on with a more rigorous scanner method that can process unicode
                                // combining-marks, connector-punctuation, and unicode escape sequences.
                                // !! note that rather than WhiteBlackLookup, we use IdentTerminatorsLookup (which removes the \\ and adds / \r \0 and
                                // special unicode line-terminators), because we need to handle a backslash in identifiers as a unicode escape 
                                // sequence:
                                if (IdentTerminatorsLookup.indexOf(streamArray[cur]) > -1) {
                                    // if we make it in here then the identifier is complete and does not have any special/complex parts:
                                    // inline token construction:
                                    
                                    String lexeme = stream.substring(index, cur);
                                    // for identifiers, we must attempt to resolve the lexeme to a keyword/reserverd-word -- unfortunately this 
                                    // requires incurring the expense of an extra hash lookup:
                                    // if the lexeme is a keyword, then the following logic will change ttype from IDENTIFIER to the appropriate
                                    // KW_ or RW_ type:
                                    Integer lookupIndex = KeywordsLookup.indexOf(lexeme) + 1;
                                    cursor.ttype = KeywordsTable[lookupIndex];
                                    // if we matched into the keyword lookup, then make sure would lexeme is the correct length for that keyword (i.e. 
                                    // we must match the whole keyword, not just the start of the keyword):
                                    if (cursor.ttype == null || cursor.ttype != IDENTIFIER && KeywordLenTable[lookupIndex] != cur - index)
                                        cursor.ttype = IDENTIFIER;
                                    
                                    Token tok = cursor.clone();
                                    cursor.index = cur;
                                    cursor.col += cur - index;
                                    tok.lexeme = lexeme;
                                    toks[++top] = tok;
                                    continue;
                                
                                // else, we have an identifier that -- while is has a common start char, it does not hit our "common" scenario in at
                                // least 1 parameter (i.e. contains a unicode combining-mark, connector punctuation, or unicode escape sequence, or
                                // does not end in a common terminator char). note that the scanIdentifier method is slightly less efficient than the
                                // above logic:
                                } else {
                                    toks[++top] = scanIdentifier(this, index, cur, null);
                                    continue;
                                }
                                
                            } else if (ttype == DECIMAL_NUMBER) {
                                // !! note that the following scanner logic in inlined for performance, but we could call scanDecimalNum for cleaner
                                // code.
                                // !! here, we know that ch1 is a digit [1-9]
                                Integer cur = index + 1; // we already know ch1 is a digit [1-9]
                                Integer digitType;
                                // states:
                                // 0 => start state; valid integer part
                                // 1 => decimal part; valid
                                // 2 => exponent, not yet valid (needs at least 1 digit)
                                // 3 => exponent, valid
                                Integer state = 0;
                                // scan [0-9] '.' and [eE] chars:
                                while ((digitType = DecimalDigits.indexOf(streamArray[cur])) > -1) {
                                    // we got a digit [0-9]:
                                    if (digitType < 10) {
                                        // a digit on an exponent makes it valid:
                                        if (state == 2)
                                            state = 3;
                                    // we got a '.' char:
                                    } else if (digitType == 10) {
                                        // only state 0 accepts a decimal:
                                        if (state != 0)
                                            break;
                                        // state 0 proceeds to state 1 when it gets a decimal:
                                        else
                                            state = 1;
                                    // else, we must have an [eE] exponent:
                                    } else {
                                        // we can't accept another exponent if we're already in that state:
                                        if (state > 1)
                                            break;
                                        // go directly to state 2:
                                        state = 2;
                                        // check for a [+-] sign, and advance past it:
                                        if (PlusMinusChars.indexOf(streamArray[cur + 1]) > -1)
                                            cur++;
                                    }
                                    cur++;
                                }
                                
                                // a decimal number cannot end in an [eE] that does not have 1 or more subsequent exponent digits:
                                if (state == 2)
                                    throw new ScanException(0, 'invalid decimal number');
                                
                                // inline token construction:
                                cursor.ttype = DECIMAL_NUMBER;
                                Token tok = cursor.clone();
                                tok.lexeme = stream.substring(index, cur);
                                cursor.index = cur;
                                cursor.col += cur - index;
                                toks[++top] = tok;
                                continue;
                            }
                        
                        } else if (tsRes1 == TS_SQ_STRING || tsRes1 == TS_DQ_STRING) {
                            // advance past the leading quote-char:
                            Integer cur = index + 1;
                            String terminatingChars = tsRes1 == TS_SQ_STRING ? NormalModeBreakingCharsSQ : NormalModeBreakingCharsDQ;
                            // scan chars until we encounter a terminating quote (of matching flavor) or a line-terminator:
                            while (!terminatingChars.contains(streamArray[cur]))
                                cur++;
                            
                            // if we're looking at the same quote-char that started the string, then we've successfully scanned a simple string:
                            if (streamArray[cur].equals(ch1)) {
                                // strips the enclosing quotes:
                                String slex = stream.substring(index + 1, cur);
                                // inline token construction...for great justice:
                                cursor.ttype = STRING_LITERAL;
                                Token tok = cursor.clone();
                                tok.lexeme = slex;
                                // compensate by +1 for the outer quotes we've stripped:
                                cursor.index += slex.length() + 2;
                                cursor.col += slex.length() + 2;
                                toks[++top] = tok;
                                continue;
                                
                            // else, we have either a complex string or an invalid string; use the more rigorous (but far slower) scanner:
                            } else {
                                toks[++top] = scanStringLit(this, index, cur, tsRes1 == TS_DQ_STRING);
                                continue;
                            }
                            
                        // else, we got either TS_NEXT or TS_LEAD_ZERO; we must investigate 2 lookahead chars to determine the next action:
                        } else {
                            Integer tsIndex2, tsRes2;
                            String ch2 = stream.mid(index, 2);
                            // !! note that the tsRes2 != null condition prevents matches on mixed 2-char tokens, e.g. '+-':
                            if (index + 1 < streamLen && (tsIndex2 = TransStateLookup2.indexOf(ch2)) > -1 && (tsRes2 = TransStateTable2[tsIndex2]) != null) {
                                // note that DECIMAL_NUMBER and HEX_NUMBER are the only complex tokens that can be returned by tsMap2:
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
                                } else if ((tsRes2 & TOKEN_MASK) == DECIMAL_NUMBER) {
                                    // we have a 0[0-9] (i.e. starting-state 0):
                                    if ((tsRes2 & TS_MASK) == TS_DECIMAL_STATE0)
                                        toks[++top] = scanDecimalNum(this, 0, index, index + 2);
                                    // else, we must have a \.[0-9] (i.e. starting-state 1):
                                    else
                                        toks[++top] = scanDecimalNum(this, 1, index, index + 2);
                                    
                                    continue;
                                    
                                // hex number:
                                } else if ((tsRes2 & TOKEN_MASK) == HEX_NUMBER) {
                                    toks[++top] = scanHexNumber(this, index);
                                    continue;
                                
                                // else, we must hit tsMap3 for further disambiguation:
                                } else {
                                    Integer tsIndex3, tsRes3;
                                    String ch3 = stream.mid(index, 3);
                                    // !! note that the tsRes3 != null condition prevents matches on mixed 3-char tokens, e.g. '=!=':
                                    if (index + 2 < streamLen && (tsIndex3 = TransStateLookup3.indexOf(ch3)) > -1 && (tsRes3 = TransStateTable3[tsIndex3]) != null) {
                                        if (tsRes3 < TS_BIT)
                                            toks[++top] = newToken(cursor, tsRes3, ch3, null, null, null); 
                                        // else, we have '>>>' and must check for '>>>=':
                                        else
                                            if (stream.mid(index + 3, 1).equals('='))
                                                toks[++top] = newToken(cursor, ASSIGN_URIGHT_SHIFT, ch3 + '=', null, null, null);
                                            else
                                                toks[++top] = newToken(cursor, tsRes3 & TOKEN_MASK, ch3, null, null, null);
                                    // if we get no match on tsMap3, then we can always fallback to the token from the lower bits of tsRes2:
                                    } else
                                        toks[++top] = newToken(cursor, tsRes2 & TOKEN_MASK, ch2, null, null, null); 
                                    
                                    continue;
                                }
                                
                            // if we didn't match a 2-char state, then fallback as dictated by tsRes1:   
                            } else if ((tsRes1 & TS_MASK) == TS_NEXT) {
                                toks[++top] = newToken(cursor, tsRes1 & TOKEN_MASK, ch1, null, null, null);
                                continue;
                            // TODO: the case of the decimal number '0' can and probably should be optimized by inlining the token creation:
                            } else if ((tsRes1 & TS_MASK) == TS_LEAD_ZERO) {
                                toks[++top] = newToken(cursor, DECIMAL_NUMBER, ch1, null, null, null);
                                continue;
                            }
                        }
                    
                    // else, we either have an illegal token or a "difficult" token -- the latter being either 1 of the 2 division operations, a
                    // regexp, or an identifier with a lead char outside the ASCII range or a lead that is a unicode escape sequence:
                    } else {
                        // '/' is difficult because of the ambiguity between DIVIDE, ASSIGN_DIVIDE and REGEXP. if we've just received contextual
                        // feedback from the parser, then we use that to disambiguate. otherwise, we try to disambiguate "easy" cases by deciding
                        // whether the prior token looks unambiguously like data or an operator. failing that, we must appeal to the parser for
                        // contextual feedback by yielding a NEEDS_FEEDBACK token:
                        if (DivChar.equals(ch1)) {
                            Integer priorType = cursor.ttype, ttype;
                            String lexeme;
                            
                            // if we've either set a DIV_CONTEXT feedback from this scanMore call OR the prior token unambiguously looks like data,
                            // then we'll scan a division operator:
                            if (contextualFeedback == DIV_CONTEXT && contextualFeedbackTop == top 
                                    || (TokenClassifications[priorType] & TKLASS_SETS_DIV_CONTEXT) > 0) {
                                contextualFeedback = contextualFeedbackTop = null;
                                if (stream.mid(index, 2).equals('/=')) {
                                    ttype = ASSIGN_DIVIDE;
                                    lexeme = '/=';
                                } else {
                                    ttype = DIVIDE;
                                    lexeme = ch1;
                                }
                                Token newTok = newToken(cursor, ttype, lexeme, null, null, null);
                                // check whether we're replacing a NEEDS_FEEDBACK token:
                                if (toks[top].ttype == NEEDS_FEEDBACK) {
                                    // preserve/pass-along any lead boundary we collected on the scan of the NEEDS_FEEDBACK token:
                                    newTok.leadLineBreaks = toks[top].leadLineBreaks;
                                    newTok.leadComments = toks[top].leadComments;
                                    toks[top] = newTok;
                                } else 
                                    toks[++top] = newTok;
                                
                                continue;
                            // else, if we've either set a REGEXP_CONTEXT feedback from this scanMore call OR the prior token unambiguously looks
                            // like an operator, then we'll scan a regexp:
                            } else if (contextualFeedback == REGEXP_CONTEXT && contextualFeedbackTop == top 
                                    // the following prior tokens have ambiguous meaning at the scanner level; they always require parser feedback to
                                    // determine the correct context (e.g. is a '}' the end of an object-literal or a code block? e.g. is the '++'
                                    // a prefix or postfix inc op?):
                                    || (priorType != CLOSE_BRACE && priorType != INCREMENT && priorType != DECREMENT)) {
                                contextualFeedback = contextualFeedbackTop = null;
                                Token newTok = scanRegexp(this, index);
                                // check whether we're replacing a NEEDS_FEEDBACK token:
                                if (toks[top].ttype == NEEDS_FEEDBACK) {
                                    // preserve/pass-along any lead boundary we collected on the scan of the NEEDS_FEEDBACK token:
                                    newTok.leadLineBreaks = toks[top].leadLineBreaks;
                                    newTok.leadComments = toks[top].leadComments;
                                    toks[top] = newTok;
                                } else 
                                    toks[++top] = newTok;
                                
                                continue;
                            // else we need feedback from the parser:
                            } else {
                                Token cursorSavepoint = cursor.clone();
                                toks[++top] = newToken(cursor, NEEDS_FEEDBACK, '/', null, null, null);
                                // rollback the cursor to point before the lead '/' char, since we'll need to scan it again after receiving feedback;
                                // note though, that the cursorSavepoint will have advanced beyond the lead boundary:
                                this.cursor = cursorSavepoint;
                                // halt the scanning loop in order to provide the parser an opportunity to set a feedback context:
                                break;
                            }
                            
                        // an identifier may have slipped through the cracks with a lead char that is a unicode letter outside the traditional ASCII
                        // range; fortunately the Apex String class has a native method to match unicode letters that's not horribly slow:
                        } else if (ch1.isAlpha() || '\\'.equals(ch1)) {
                            // see ECMA-262 7.8.3:
                            if (!hasLead && (cursor.ttype == HEX_NUMBER || cursor.ttype == DECIMAL_NUMBER))
                                throw new ScanException(0, 'identifier cannot follow number without a separating boundary');

                            toks[++top] = scanIdentifier(this, index, index, null);
                            continue;
                        }
                        
                        // TODO: as a last-ditch effort, we may be dealing with a nefarious indetifier that starts with a unicode Number-letter \p{Nl}
                        // (e.g. roman numerals, etc)...I guess we have to invoke a nasty expensive regexp to check \p{Nl} in these situations...
                        
                    }
                    
                    // crud, I guess we have an illegal token:
                    throw new ScanException(0, streamArray[index]);
                }
            // scanToken loop ends once we've encountered the EOF token:
            } while (termEOF == null);
        } catch (ScanException e) {
            
            // !! note that cursor has already been incremented by the lead boundary (if any), but not by the failed/illegal token. this means that
            // the lead token's lexeme/data will be "lost" after this failure, but this should not be an issue since there is no potential/need 
            // for error recovery (i.e. no continued scanning) after any of the ScanExceptions: 
            Token errorLoc = cursor.clone();
            errorLoc.index += e.offendingOffsetChars;
            if (e.offendingOffsetLines > 0) {
                errorLoc.line += e.offendingOffsetLines;
                errorLoc.col = e.offendingOffsetCol;
            }
            //System.assert(false, 'ERROR: ' + e.msg);
            throw new ParseException(e.msg, errorLoc);
        } finally {
            // clear out some of the input text to save heap space:
            // !! keep stream around to validate Directive Prologues and to provide the literal source code for functions:
            //stream = null;
            streamArray = null;
        }
    }
    
    static Token termEOF(Token cursor) {
        return newToken(cursor, EOF, '<EOF>', null, null, null);
    }
    
    // takes the starting state as a parameter, since in some cases we wish to start scanning after a decimal:
    static Token scanDecimalNum(Lexer2 lex, Integer state, Integer index, Integer cur) {
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
                if (state == 2)
                    state = 3;
            // we got a '.' char:
            } else if (digitType == 10) {
                // only state 0 accepts a decimal:
                if (state != 0)
                    break;
                // state 0 proceeds to state 1 when it gets a decimal:
                else
                    state = 1;
            // else, we must have an [eE] exponent:
            } else {
                // we can't accept another exponent if we're already in that state:
                if (state > 1)
                    break;
                // go directly to state 2:
                state = 2;
                // check for a [+-] sign, and advance past it:
                if (PlusMinusChars.indexOf(streamArray[cur + 1]) > -1)
                    cur++;
            }
            cur++;
        }
        
        // a decimal number cannot end in an [eE] that does not have 1 or more subsequent exponent digits:
        if (state == 2)
            throw new ScanException(0, 'invalid decimal number');
        
        // inline token construction...for great justice:
        Token cursor = lex.cursor;
        cursor.ttype = DECIMAL_NUMBER;
        Token tok = cursor.clone();
        cursor.index = cur;
        cursor.col += cur - index;
        tok.lexeme = lex.stream.substring(index, cur);
        return tok;
    }
    
    static Token scanHexNumber(Lexer2 lex, Integer index) {
        Integer cur = index + 2;
        String[] streamArray = lex.streamArray;
        while (HexadecimalDigits.indexOfIgnoreCase(streamArray[cur]) > -1) {
            cur++;
        }
        
        if (cur == index + 2)
            throw new ScanException(0, 'hexadecimal number has no digits');
        
        // inline token construction:
        Token cursor = lex.cursor;
        cursor.ttype = HEX_NUMBER;
        Token tok = cursor.clone();
        tok.lexeme = lex.stream.substring(index + 2, cur);
        cursor.index = cur;
        cursor.col += cur - index;
        return tok;
    }
    
    // rigorously scans identifiers according to the ECMA-262 spec
    // !! if we're starting on the lead char (i.e. index == cur), and that lead is not a '\', then this method assumes that the char
    // has already been validated as a legal identifier start-char; it will not re-validate this. however, it will validate that 
    // a leading unicode escape sequence yields a valid identifier start char.
    // !! a non-null regexpToken indicates that we should scan only an ECMA-262 "IdentifierPart" for use as flags in a RegExp:
    static Token scanIdentifier(Lexer2 lex, Integer index, Integer cur, Token regexpToken) {
        String[] streamArray = lex.streamArray;
        Integer state = 0;
        // states:
        // 0 => normal mode; we are not currently inside an escape sequence
        // 1 => in a unicode esc-sequence; has 0 digits; invalid until we get 4
        // 2 => in a unicode esc-sequence; has 1 digit; invalid until we get 4
        // 3 => in a unicode esc-sequence; has 2 digits; invalid until we get 4
        // 4 => in a unicode esc-sequence; has 3 digits; invalid until we get 4
        String[] parts; // processed parts; to be joined on final token creation
        Integer lastPartEnd = index;
        Integer hexValue;
        String ch;
        Boolean isLeadEsc;
        // quite literally, set to true if we encountered a unicode escape char yields a char that is "hard" to validate without the aid of a Matcher
        // (e.g. unicode combining-mark):
        Boolean hasTrickseyEsc;
        do {
            if (state == 0) {
                ch = streamArray[cur];
                if (ch.isAlphanumeric() || AdditionalIdentPartChars.contains(ch)) {
                    cur++;
                } else if (IdentTerminatorsLookup.indexOf(ch) > -1) {
                    break;
                } else if ('\\'.equals(ch)) {
                    state = 1;
                    isLeadEsc = index == cur;
                    if (cur > lastPartEnd) {
                        ch = lex.stream.substring(lastPartEnd, cur);
                        if (parts == null)
                            parts = new String[]{ ch };
                        else 
                            parts.add(ch);
                    }
                    if ('u'.equals(streamArray[cur + 1]))
                        cur += 2;
                    else
                        throw new ScanException(cur, 'invalid escape sequence in identifier');
                
                // expensive fallthrough:
                // if we're on a "start" char and we couldn't identify it above, then we use a rigorous matcher that will identify all the 
                // nefarious unicode "IndetifierStart" chars: [$_]/unicode-letter/unicode-number-letter -- it also
                // matches as far into the identifier as possible (breaking only for unicode escape sequences), since we've already invoked 
                // the huge overhead of the matcher:
                } else if (cur == index && lex.identStartWithNefariousCharsMatcher.region(cur, lex.streamLen).lookingAt()) {
                    cur = lex.identStartWithNefariousCharsMatcher.end();
                    
                // expensive fallthrough:
                // if we're on a "part" char and we couldn't identify it above, then we use a rigorous matcher that will identify all the 
                // nefarious unicode "IndetifierPart" chars: [$_]/unicode-letter/unicode-number-letter/unicode-number-digit/<ZWJ>/<ZWNJ>/
                // combining-marks/non-spacing-marks/connector-punctuation -- it also matches as far into the identifier as possible (breaking 
                // only for unicode escape sequences), since we've already invoked the huge overhead of the matcher:
                } else if (cur > index && lex.identPartWithNefariousCharsMatcher.region(cur, lex.streamLen).lookingAt()) {
                    cur = lex.identPartWithNefariousCharsMatcher.end();
                    
                // else, we cannot recognize the next char at all, and thus it must terminate the identifier:
                } else 
                    break;
            // else, we must be in a unicode escape sequence:
            } else {
                Integer digitVal;
                if ((digitVal = HexadecimalDigits.indexOfIgnoreCase(streamArray[cur])) > -1) {
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
                        ch = String.fromCharArray(new Integer[] { hexValue });
                        
                        // try to verify the validity of the char produced by the unicode escape sequence:
                        if (isLeadEsc && regexpToken == null) {
                            if (!ch.isAlpha() && !AdditionalIdentStartChars.contains(ch))
                                throw new ScanException(0, 'identifier\'s leading unicode escape sequence yielded an invalid start character');
                        } else if (hasTrickseyEsc != true && !ch.isAlphanumeric() && !AdditionalIdentPartChars.contains(ch)) {
                            // this is not easy to verify; it may be a unicode oddball like a combining-mark or connector punctuation -- we'll defer 
                            // the serious validation for later:
                            hasTrickseyEsc = true;
                        }
                        
                        if (parts == null)
                            parts = new String[]{ ch };
                        else 
                            parts.add(ch);
                        
                        lastPartEnd = ++cur;
                        continue;
                    }
                    cur++;
                } else
                    throw new ScanException(cur, 'an identifier\'s unicode escape sequence may only contain hexadecimal digits');
            }
        } while (true);
        
        if (state > 0)
            throw new ScanException(cur, 'identifier has an incomplete unicode escape sequence');
        
        // inline token construction:
        String lexeme;
        if (parts == null) 
            lexeme = lex.stream.substring(index, cur);
        else {
            if (cur > lastPartEnd)
                parts.add(lex.stream.substring(lastPartEnd, cur));
            
            lexeme = String.join(parts, '');
        }
        
        // if we processed a "tricksey" unicode escape sequence, then we'll validate the whole shebang at once, since this regexp match is expensive
        // like a Kanye West T-shirt:
        if (hasTrickseyEsc == true && !(regexpToken == null ? ValidUnescapedIdentifierWholePatt : ValidUnescapedIdentifierPartPatt).matcher(lexeme).matches())
            throw new ScanException(0, 'identifier contains an unacceptable unicode escape sequence');
        
        // if we scanned a whole, standalone identifier token:
        if (regexpToken == null) {
            // if the lexeme is a keyword, then the following logic will change ttype from IDENTIFIER to the appropriate KW_ or RW_ type:
            Token cursor = lex.cursor;
            cursor.ttype = KeywordsTable[KeywordsLookup.indexOf(lexeme) + 1];
            Token tok = cursor.clone();
            tok.lexeme = lexeme;
            cursor.index = cur;
            cursor.col += cur - index;
            return tok;
        // else, we scanned an identifier part for a regexp's flags:
        } else {
            Token cursor = lex.cursor;
            cursor.index = cur;
            cursor.col += cur - index;
            regexpToken.regexpFlags = lexeme;
            return regexpToken;
        }
    }
    
    static final String StringEscapeTypesLookup = '0xu\n\r' + UnicodeSpecialLineTerminators + '\'"\\bfnrtv';
    static final String[] StringEscapeTypeTable = new String[]{ String.fromCharArray(new Integer[]{ 0 }), null, null, null, null, null, null, '\'', '"', '\\', '\b', '\f', '\n', '\r', '\t', String.fromCharArray(new Integer[]{ 11 }) };
    
    // rigorously scans string literals according to the ECMA-262 spec
    static Token scanStringLit(Lexer2 lex, Integer index, Integer cur, Boolean isDQ) {
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
        Integer lastPartEnd = index + 1; // remember to advance past the starting quote char
        Integer hexValue;
        String ch;
        // if non-null, this stores the value of cur at the time the last line-continuation escape sequence was encountered (points past those line-
        // break chars):
        Integer lastContinuationCur;
        Integer lineContinuationCount = 0;
        do {
            if (state == 0) {
                if (!normalModeBreakingChars.contains(ch = streamArray[cur]))
                    cur++;
                else if ('\\'.equals(ch)) {
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
                            if (escType == 4 && '\n'.equals(streamArray[cur + 2]))
                                cur = cur += 3;
                            else 
                                cur += 2;
                            
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
                } else
                    break;
                
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
                } else
                    throw new ScanException(cur, 'a string literal\'s unicode escape sequence may only contain hexadecimal digits');

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
                } else
                    throw new ScanException(cur, 'a string literal\'s unicode escape sequence may only contain hexadecimal digits');
            }
        } while (true);
        
        if (state > 0)
            if (state < 5)
                throw new ScanException(cur, 'string literal has an incomplete unicode escape sequence');
            else
                throw new ScanException(cur, 'string literal has an incomplete hex escape sequence');
        
        // verify that cur points at the correct terminating quote char:
        if (!(isDQ ? '"' : '\'').equals(streamArray[cur])) {
            if (cur >= lex.streamLen)
                throw new ScanException(cur, 'unexpected end-of-file encountered in string literal');
            else 
                throw new ScanException(cur, 'illegal line-break in string literal');
        }
        
        // inline token construction:
        Token cursor = lex.cursor;
        cursor.ttype = STRING_LITERAL;
        Token tok = cursor.clone();
        cursor.index = cur + 1; // advance past the terminating quote char
        
        if (lineContinuationCount > 0)
            cursor.line += lineContinuationCount;
        
        if (lineContinuationCount > 0)
            cursor.col = cur - lastContinuationCur + 1; // add 1 to get past the terminating quote char
        else 
            cursor.col += cur - index + 1; // add 1 to get past the terminating quote char
        
        if (parts.size() == 0) 
            tok.lexeme = lex.stream.substring(index + 1, cur);
        else {
            if (cur > lastPartEnd)
                parts.add(lex.stream.substring(lastPartEnd, cur));
            
            tok.lexeme = String.join(parts, '');
        }
        return tok;
    }
    
    // the first two -- backslash and '[' -- are valid start chars; the \0 may be valid or may indicate EOF; the remaining chars represent invalid
    // start chars:
    static final String RegexpStartCharsLookup = '\\[' + String.fromCharArray(new Integer[]{ 0 }) + '*/\n\r' + String.fromCharArray(new Integer[]{ 2028, 2029 });
    static final String RegexpCharsLookup = '\\[]/' + String.fromCharArray(new Integer[]{ 0 }) + '\n\r' + String.fromCharArray(new Integer[]{ 2028, 2029 });
    
    static Token scanRegexp(Lexer2 lex, Integer index) {
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
            if (charType > 4 || charType == 4 && cur >= lex.streamLen)
                // we backtrack so that the next iteration can choke on the illegal line-terminator or EOF:
                cur--;
        // a lead '[' denotes the start of a char-class:
        } else if (charType == 1) {
            state = 1;
        // check for EOF on a lead \0:
        } else if (charType == 2) {
            if (cur >= lex.streamLen)
                throw new ScanException(cur, 'encountered unexpected end-of-file in regular expression');
        // '/' '*' and line-terminators are illegal starts to a regexp:
        } else if (charType > 2) {
            if (charType > 4)
                throw new ScanException(cur, 'illegal line-break to start regular expression');
            // '/' and '*' are illegal, though in reality this code is unreachable because we will have scanned them as a comment already:
            else
                throw new ScanException(cur, 'illegal start to regular expression \'' + streamArray[cur - 1] + '\'');
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
                if (charType < 4 || charType == 4 && cur < lex.streamLen)
                    continue;
                // else, we backtrack so that the next iteration can choke on the illegal line-terminator or EOF:
                else
                    cur--;
            // a '[' increments the nested char-class count:
            } else if (charType == 1) {
                state++;
            // a ']' decrements the nested char-class count iff we're currently in a char-class:
            } else if (charType == 2) {
                if (state > 0)
                    state--;
            // '/' terminates only if we're not in a char-class
            } else if (charType == 3) {
                if (state < 1)
                    break;
            // \0 is a potential EOF
            } else if (charType == 4) {
                if (cur >= lex.streamLen)
                    throw new ScanException(cur, 'encountered unexpected end-of-file in regular expression');
            // else, must be > 4, hence an illegal line-terminator:
            } else {
                throw new ScanException(cur, 'illegal line-break in regular expression');
            }
        } while (true);
        
        // inline token construction:
        Token cursor = lex.cursor;
        cursor.ttype = REGEXP;
        Token tok = cursor.clone();
        tok.lexeme = lex.stream.substring(index + 1, cur - 1);
        cursor.index = cur;
        cursor.col += cur - index;
        // scan the regexp flags; when we pass a regexp token to scanIdentifier, it will scan a partial identifier and set it into the token's
        // regexpFlags:
        return scanIdentifier(lex, cur, cur, tok);
    }
    
    public void unexpectedToken(String expectedMsg) {
        Token tok = toks[next];
        throw new ParseException((expectedMsg == null ? 'Encountered unexpected ' : expectedMsg + ', but encountered unexpected ') 
                + serializeToken(tok), tok);
    }
    
    public void backUnexpectedToken(String expectedMsg) {
        next--;
        unexpectedToken(expectedMsg);
    }
    
    public void mismatch(Integer expectedTokenType, String matchContextMsg, Token contextualLoc) {
        throw new ParseException('Expected ' + serializeToken(expectedTokenType) + ' ' + matchContextMsg 
                + (contextualLoc != null ? ' [line ' + (contextualLoc.line + 1) + ', col ' + (contextualLoc.col + 1) + ']; ' : '; ')
                + 'encountered unexpected ' + serializeToken(toks[next]), toks[next]);
    }
    
    // like mismatch, except the mismatch token is expected to be 1 back from the current next position. this method will --next
    // and then throw the mismatch exception:
    public void backMismatch(Integer expectedTokenType, String matchContextMsg, Token contextualLoc) {
        next--;
        mismatch(expectedTokenType, matchContextMsg, contextualLoc);
    }
    
    public void mismatch(Integer expectedType, String matchContextMsg) {
        mismatch(expectedType, matchContextMsg, null);
    }
    
    public void backMismatch(Integer expectedType, String matchContextMsg) {
        backMismatch(expectedType, matchContextMsg, null);
    }

    public static String serializeToken(Integer ttype) {
        if (ttype == STRING_LITERAL) {
            return 'string literal';
        } else if (ttype == HEX_NUMBER) {
            return 'hex number';
        } else if (ttype == DECIMAL_NUMBER) {
            return 'decimal number';
        } else if (ttype == IDENTIFIER) {
            return 'identifier';
        } else if (ttype >= KEYWORD_MINIMUM && ttype < RESERVED_WORD_MINIMUM) {
            if (ttype == KW_NULL) {
                return '\'null\'';
            } else if (ttype == KW_NEW) {
                return '\'new\'';
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
        } else if (ttype == REGEXP) {
            return 'regular expression';
        } else if (ttype == EOF) {
            return 'end of file';
        } else if (ttype == NEEDS_FEEDBACK) {
            // we know a NEEDS_FEEDBACK token starts with a '/':
            return '/';
        } else {
            // TODO:
            return '<ttype ' + ttype + '>';
//            return ttype.name().toLowerCase();
        }
    }
    
    public static String serializeToken(Token tok) {
        if (tok.ttype == STRING_LITERAL) {
            return 'string literal \'' + tok.lexeme + '\'';
        } else if (tok.ttype == HEX_NUMBER) {
            return 'hex number \'0x' + tok.lexeme + '\'';
        } else if (tok.ttype == DECIMAL_NUMBER) {
            return 'decimal number \'' + tok.lexeme + '\'';
        } else if (tok.ttype == IDENTIFIER) {
            return 'identifier \'' + tok.lexeme + '\'';
        } else if (tok.ttype >= KEYWORD_MINIMUM && tok.ttype < RESERVED_WORD_MINIMUM) {
            if (tok.ttype == KW_NULL) {
                return '\'null\'';
            } else if (tok.ttype == KW_NEW) {
                return '\'new\'';
            } else if (tok.ttype == KW_FALSE) {
                return '\'false\'';
            } else if (tok.ttype == KW_TRUE) {
                return '\'true\'';
            } else {
                return 'keyword \'' + tok.lexeme + '\'';
            }
        } else if (tok.ttype >= RESERVED_WORD_MINIMUM) {
            return 'reserved word \'' + tok.lexeme + '\'';
        } else if (tok.ttype == REGEXP) {
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
    
    global class Token {
        public Integer ttype;
        // !! lexeme must not be null
        public String lexeme;
        
        public Integer leadLineBreaks;
        public String[] leadComments;
        public Integer index;
        public Integer line;
        public Integer col;
        public String moduleURI;
        
        public String regexpFlags;
        
        Token setRegexpFlags(String flags) {
            if (flags == null)
                this.regexpFlags = '';
            else 
                this.regexpFlags = flags;

            return this;
        }
    }
    
    // !! after cloning the following prototype, client code will need to set lead and loc appropriately:
    public static Token ProtoAutomaticSemicolon = new Token();
    static {
        ProtoAutomaticSemicolon.ttype = SEMICOLON;
        ProtoAutomaticSemicolon.lexeme = ';';
    }
    
    // when a scan-exception is thrown, the current lexer.cursor loc is expected to point at the error's source-code location, minus
    // any lead-boundary and offset:
    class ScanException extends Exception {
        // specifies that the error occurred precisely this number of chars/lines past the end of the lead boundary:
        // errorIndex = lex.cursor.index + lead.lexeme.length() + offendingOffsetChars
        Integer offendingOffsetChars = 0;
        // if the offset includes 1 or more line-breaks, the count is recorded here;
        // errorLine = lex.cursor.line + lead.lineBreaks + offendingOffsetLines
        Integer offendingOffsetLines = 0;
        // if the offset includes 1 or more line-breaks, then this must be non-null and it represents the col of the error location:
        // errorLine = offendingOffsetCol != null ? offendingOffsetCol : (lex.cursor + lead).col
        Integer offendingOffsetCol;
        String msg;
        
        // use this when the offset is guaranteed to not contain line-breaks (e.g. identifier unicode escape errors):
        ScanException(Integer offendingOffsetChars, String msg) {
            this.offendingOffsetChars = offendingOffsetChars;
            this.msg = msg == null ? 'Illegal token' : 'Illegal token: ' + msg;
        }
        
        ScanException(Integer offendingOffsetChars, Integer offendingOffsetLines, Integer offendingOffsetCol, String msg) {
            this(offendingOffsetChars, msg);
            this.offendingOffsetLines = offendingOffsetLines;
            this.offendingOffsetCol = offendingOffsetCol;
        }
    }
    
    // upon instantiation, we scan all tokens to be found in srcCode into the "toks" buffer
    // !! for the sake of efficiency, this may produce a toks array where toks.size() is greater than the actual # of 
    // scanned tokens (i.e. it may be end-padded with nulls). however, it is guaranteed to have a terminating <EOF> token 
    // before the end-padded nulls. parsers should interpret the encounter of an <EOF> as end-of-stream, OR may use lmt to
    // determine the <EOF> token -- they should not use toks.size():
    global static Lexer2 newLexer(String moduleURI, String srcCode) {
        Lexer2 lex = ProtoLexer.clone();
        lex.stream = srcCode;
        lex.streamArray = srcCode.split('');
        lex.streamArray.remove(0);
        lex.streamLen = srcCode.length();
        // !! append a terminating NUL char '\0', to allow simpler scanning logic that more gracefully handles tests that hit end-of-file 
        // (e.g. so that we never cause ArrayIndexOutOfBounds by looking ahead 1 char in streamArray) -- note that some of these tests will 
        // accept an actual \0 char (e.g. inside a string literal; inside a comment; inside RegExp), so they must include an additional 
        // streamLen test to disambiguate a true source \0 from an EOF:
        lex.streamArray.add(String.fromCharArray(new Integer[]{ 0 }));
        lex.identStartWithNefariousCharsMatcher = IdentStartWithNefariousCharsPatt.matcher(srcCode);
        lex.identPartWithNefariousCharsMatcher = IdentPartWithNefariousCharsPatt.matcher(srcCode);
        
        Token cur = lex.cursor = new Token();
        cur.moduleURI = moduleURI == null ? '<anonymous>' : moduleURI;
        cur.ttype = EMPTY;
        cur.line = 0;
        cur.col = 0;
        cur.index = 0;
        cur.leadLineBreaks = 0;
        cur.leadComments = null;
        
        lex.scanMore(DIV_CONTEXT);
        return lex;
    }
    
    static Lexer2 ProtoLexer = new Lexer2();
}