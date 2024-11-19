/*
 * Mike Ulveling
 * 
 * Example usage:
 * 
 * System.debug(WordifyNumber.wordifyDecimal('0078645100514708413.1400'));
 * System.debug(WordifyNumber.wordifyDecimal('00.098334'));
 * System.debug(WordifyNumber.wordifyDecimal('1234'));
 * System.debug(WordifyNumber.wordifyDecimal(3.14));
 * System.debug(WordifyNumber.wordifyDecimal('603'));
 * System.debug(WordifyNumber.wordifyDecimal(17000));
 */
public class WordifyNumber {

    public class Options {
        public String hundred = ' hundred';
        public String zero = 'zero';
        public String andJoin = ' and ';
        public String plainJoin = ' ';
        public String hyphenJoin = '-';
        //public String intDecJoin = ', ';
        public String[] ones = 'zero one two three four five six seven eight nine ten'.split(' ');
        public String[] teens = ('ten eleven twelve thirteen fouteen fifteen sixteen seventeen ' + 
                'eighteen nineteen').split(' ');
        public String[] tens = '  twenty thirty fourty fifty sixty seventy eighty ninety'.split(' ');
        public String[] qualifiers = ('thousand million billion trillion quadrillion quintillion ' + 
                'sextillion septillion octillion nonillion decillion undecillion duodecillion ' + 
                'tredecillion quattuordecillion quindecillion sexdecillion septendecillion ' + 
                'octodecillion novemdecillion vigintillion').split(' ');
        public String qualifierJoin = ', ';
        public String point = 'point';
        public String pointJoin = plainJoin + point;
    }
    
    static String[] chars(String str) {
        String[] chars = str.split('');
        if (chars.size() > 0) {
            chars.remove(0);
        }
        return chars;
    }
    
    public class FormatException extends Exception {}
    
    public static String wordifyDecimal(Decimal num) {
        return wordifyDecimal(new Options(), num);
    }
    
    public static String wordifyDecimal(String strNumber) {
        return wordifyDecimal(new Options(), strNumber);
    }
    
    public static String wordifyDecimal(Options opts, Decimal num) {
        String strNum = String.valueOf(num);
        if (strNum.indexOfIgnoreCase('e') > 0) {
            throw new FormatException('Cannot wordify numbers that are only expressible in exponential notation');
        }
        return wordifyDecimal(opts, String.valueOf(num));
    }
    
    public static String wordifyDecimal(Options opts, String strNumber) {
        Integer decimalIndex = strNumber.indexOf('.');
        if (decimalIndex >= 0) {
            String decimalWords = '';
            // strip trailing zeros from the decimal component:
            String strDecimal = strNumber.substring(decimalIndex + 1, strNumber.length()).
                    replaceAll('([^0])[0]+$', '$1');
            for (Integer i=0; i < strDecimal.length(); i++) {
                decimalWords += (i > 0 ? opts.hyphenJoin : '') + 
                        opts.ones[Integer.valueOf(strDecimal.substring(i, i+1))]; 
            }
            return wordifyInt(opts, strNumber.substring(0, decimalIndex)) + 
                    (decimalIndex > 0 ? opts.pointJoin : opts.point) + opts.plainJoin + 
                        decimalWords;
        }
        return wordifyInt(new Options(), strNumber);
    }

    public static String wordifyInt(String strInt) {
        return wordifyInt(new Options(), strInt);
    }
    
    public static String wordifyInt(Options opts, String strInt) {
        strInt = strInt == null ? '' : strInt.replaceAll('\\s', '');
        if (strInt == '') {
            return strInt;
        }
        // ensure we've got a valid int:
        if (!Pattern.compile('\\d+').matcher(strInt).matches()) {
            throw new FormatException('Invalid integer: ' + strInt);
        }
        // reduce leading zeros:
        strInt = strInt.replaceAll('^[0]+', '');
        if (strInt == '') {
            return opts.zero;
        }
        // break the integer up into millenial chunks of 3 digits, starting from the 
        // least-significant (i.e. right-most) digit:
        String buffer = '';
        Integer qualifierIndex = -1;
        for (Integer i=strInt.length() - 3; i >= -2; i -= 3) {
            if (qualifierIndex >= opts.qualifiers.size()) {
                throw new FormatException('Integer is too long');
            }
            // left-pad-0 as necessary, if we're on our most significant chunk:
            String[] chars = chars((i == -2 ? '00' : (i == -1 ? '0' : '')) + 
                    strInt.substring(Math.max(0, i), i + 3));
            String chunk = wordifyMillenia(opts, new Integer[]{
                Integer.valueOf(chars[0]), Integer.valueOf(chars[1]), Integer.valueOf(chars[2])});
            buffer = chunk + (qualifierIndex >= 0 ? opts.plainJoin + opts.qualifiers[qualifierIndex] + 
                    opts.qualifierJoin : '') + buffer;
            // apparently Apex does not support the comma operator in for loops:
            qualifierIndex++;
        }
        return buffer.replaceAll('\\s*+\\,\\s*+$', '');
    }
    
    // takes in 3 digits representing a "millenia", with index 0 being the most significant 
    // digits (i.e. hundreds) and first breaks it down into an array of 3 string 'bits', some 
    // or all of which may be null -- e.g. 805 => {'eight', null, 'five'}, 034 => 
    // {null, 'thirty', 'four'}, 217 => {'two', 'seventeen', null} -- and then joins those bits according 
    // to options. 
    static String wordifyMillenia(Options opts, Integer[] digits) {
        String[] bits = new String[]{null, null, null};
        // hundreds column:
        if (digits[0] > 0) {
            bits[0] = opts.ones[digits[0]];
        }
        // tens column:
        if (digits[1] == 1) {
            // 1 in the decades column -- e.g. eleven, sixteen:
            bits[1] = opts.teens[digits[2]];
            return joinBits(opts, bits);
        } else if (digits[1] > 1) {
            bits[1] = opts.tens[digits[1]];
        }
        // ones column:
        if (digits[2] > 0) {
            bits[2] = opts.ones[digits[2]];
        }
        return joinBits(opts, bits);
    }
    
    static String joinBits(Options opts, String[] bits) {
        String buffer = '';
        if (bits[0] != null) {
            buffer += bits[0] + opts.hundred;
        }
        if (bits[1] != null) {
            buffer += (bits[0] != null ? opts.andJoin : '') + bits[1] + 
                    (bits[2] != null ? opts.hyphenJoin + bits[2] : '');
        } else if (bits[2] != null) {
            buffer += (bits[0] != null ? opts.andJoin : '') + bits[2];
        }
        return buffer;
    }
}