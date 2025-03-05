/*
 * Mike Ulveling
 *
 * This serializer outputs a parsed condition expression in strict SOQL syntax. Any custom reference processing and parameter value 
 * bindings should be performed before traversing a CondExpr with this visitor.
 */
global virtual class SOQLEvaluator extends SOQLParser.Visitor {
    
    public class EvaluatorException extends Exception {}

    SOQLContext context;
    SOQLParser.SOQL soql;
    
    Boolean withBinds = false;
    sObject bindingRecord;

    // SOQLEvaluator instances should only be minted through SOQLContext instance methods:
    // getEvaluatorWithoutBinds()
    // getEvaluatorWithBinds()
    public SOQLEvaluator(SOQLContext context, SOQLParser.SOQL soql) {
        this.context = context;
        this.soql = soql;
    }

    public SOQLParser.SOQL getSOQL() {
        return this.soql;
    }

    global SOQLEvaluator withoutBinds() {
        this.withBinds = false;
        return this;
    }

    global SOQLEvaluator withBinds() {
        this.withBinds = true;
        return this;
    }

    global Boolean eval(SObject targetRecord) {
        this.bindingRecord = targetRecord;
        SOQLParser.CondExpr whereCond = soql.whereCond;
        whereCond.eval = null;
        whereCond.traverse(this);
        return whereCond.eval == true;
    }

    global String[] evalDebug(SObject targetRecord) {
        Boolean evalResult = eval(targetRecord);
        SOQLParser.EvalDebug debug = new SOQLParser.EvalDebug();
        soql.whereCond.traverse(debug);
        return debug.printResults();
    }
    
    global void evalMatchSubResults(SObject targetRecord, Boolean[] expectedSubResults) {
        Boolean evalResult = eval(targetRecord);
        SOQLParser.EvalDebug debug = new SOQLParser.EvalDebug();
        soql.whereCond.traverse(debug);
        System.assert(expectedSubResults != null && expectedSubResults.size() > 0, 'Expected sub-condition results cannot be null or empty');
        System.assert(expectedSubResults.size() == debug.results.size(), 
            'Expected number of sub-conditions ' + expectedSubResults + ' does not match actual number of sub-conditions ' + debug.results.size());
        for (Integer i=0; i < expectedSubResults.size(); i++) {
            if (expectedSubResults[i] != debug.results[i]) {
                System.assert(false, 'Sub-condition #' + (i + 1) + ' did not match expected result ' + 
                              expectedSubResults[i] + '; sub-condition: [' + debug.parts[i].ser() + '] => ' + debug.results[i]);
            }
        }
    }

    public virtual override Boolean visit(SOQLParser.OrExpr orExpr) {
        if (orExpr.isEmpty()) {
            // null is treated as a "neutral" value by And/Or/Not exprs -- this is so that "empty" terms on either side of a binary logical operator
            // don't influence the result (e.g. "false OR <empty>" should resolve to false):
            orExpr.eval = null;
            return false;
        } else {
            return true;
        }
    }

    public virtual override void afterVisit(SOQLParser.OrExpr orExpr) {
        orExpr.eval = false;
        Integer len = orExpr.children.size();
        for (Integer i=0; i < len; i++) {
            if (orExpr.children[i].eval == true) {
                orExpr.eval = true;
                break;
            }
        }
    }

    public virtual override Boolean visit(SOQLParser.AndExpr andExpr) {
        if (andExpr.isEmpty()) {
            // null is treated as a "neutral" value by And/Or/Not exprs -- this is so that "empty" terms on either side of a binary logical operator
            // don't influence the result (e.g. "true AND <empty>" should resolve to true):
            andExpr.eval = null;
            return false;
        } else {
            return true;
        }
    }

    public virtual override void afterVisit(SOQLParser.AndExpr andExpr) {
        andExpr.eval = true;
        Integer len = andExpr.children.size();
        for (Integer i=0; i < len; i++) {
            if (andExpr.children[i].eval == false) {
                andExpr.eval = false;
                break;
            }
        }
    }

    public virtual override Boolean visit(SOQLParser.NotExpr notExpr) {
        if (notExpr.isEmpty()) {
            // null is treated as a "neutral" value by And/Or/Not exprs -- this is so that "empty" terms on either side of a binary logical operator
            // don't influence the result (e.g. "true AND NOT(<empty>)" should resolve to true; "false OR NOT(<empty>)" should resolve to false):
            notExpr.eval = null;
            return false;
        } else {
            return true;
        }
    }

    public virtual override void afterVisit(SOQLParser.NotExpr notExpr) {
        notExpr.eval = notExpr.operand.eval == false;
    }

    // SimpleExpr is the lowest level at which a visitor method performs eval calculations. Becasue of this, we do not require any aggregated visitor
    // information from lower levels, and this we can implement the eval logic in the before-visit and cancel subsequent traversal. Note that the one
    // exception to this is when this SimpleExpr holds a nested SimpleExpr; in that case we must allow traversal and aggregation to this child nested.
    public virtual override Boolean visit(SOQLParser.SimpleExpr simp) {
        if (simp.nested != null) {
            // allow traversal through the nested SimpleExpr:
            return true;
        }

        // just-in-time and if necessary (i.e. if simpleExpr.ref.refProc is null, then simpleExpr.ref.fieldType is also guaranteed to 
        // be null), run this serializer's ReferenceProcessor instance over simpleExpr.ref:
        // TODO: should we also check for incompatible baseRefType? (no; let user shoot themselves in foot if they resolve refs under 
        // one sObjectType and then eval against another type):
        //if (simp.ref.refProc == null && refProc != null) {
        //    // this call may throw a ReferenceException, depending on this.refProc's settings:
        //    refProc.visit(simp.ref);
        //}

        if (simp.ref.refHead == null) {
            SOQLParser.evalErr(simp.ref.names[0], 'Reference ' + simp.ref.toString() + ' is unresolved');
        }

        Schema.SOAPType lhsSoapType;
        // resolve the lhs value by de-referencing ref names through the binding record:
        Object lhsVal;
        SOQLParser.RefDesc refNode = simp.ref.refHead;
        if (refNode.isDynamic) {
            System.assert(false, 'Dynamic reference evaluation not yet implemented');
            // TODO: re-enable, test...
            /*
            Map<String, Object> holder = this.bindingMap;
            while (refNode != null && refNode.next != null && holder != null) {
                Object o = holder.get(refNode.name);
                // TODO: make scrict null-dereferences an Evaluator setting:
                if (o == null || o instanceof Map<String, Object>) {
                    holder = (Map<String, Object>) o;
                } else {
                    SOQLParser.evalErr(refNode.getSrcToken(), 'Dynamic reference ' + refNode.getResolvedDescripString() + 
                        ' was expected to return a generic map object; got unexpected value ' + o);
                }
                refNode = refNode.next;
            }
            refNode = simp.ref.refTail;
            if (holder != null) {
                lhsVal = holder.get(refNode.name);
            }
            if (lhsVal != null) {
                if (lhsVal instanceof String) {
                    lhsSoapType = Schema.SOAPType.String;
                } else if (lhsVal instanceof Decimal) {
                    lhsSoapType = Schema.SOAPType.Double;
                } else if (lhsVal instanceof Boolean) {
                    lhsSoapType = Schema.SOAPType.Boolean;
                } else if (lhsVal instanceof Date) {
                    lhsSoapType = Schema.SOAPType.Date;
                } else if (lhsVal instanceof DateTime) {
                    lhsSoapType = Schema.SOAPType.DateTime;
                } else if (lhsVal instanceof Id) {
                    lhsSoapType = Schema.SOAPType.Id;
                } else if (lhsVal instanceof sObject) {
                    lhsSoapType = Schema.SOAPType.Id;
                    lhsVal = ((sObject) lhsVal).Id;
                } else {
                    SOQLParser.evalErr(refNode.getSrcToken(), 'Dynamic reference ' + simp.ref.getFullResolvedDescripString() + 
                        ' was expected to return a primitive value type; got unexpected value ' + lhsVal);
                }
            }
            */
        } else {
            if (simp.ref.fieldTypeToken == null) {
                SOQLParser.evalErr(simp.ref.names[0], 'sObject reference ' + simp.ref.getFullResolvedDescripString() + ' to Object type ' + 
                    bindingRecord.getSObjectType() + ' could not be resolved');
            }
            //lhsSoapType = simp.ref.fieldType.getSoapType();
            lhsSoapType = simp.ref.fieldSoapType;
            sObject holder = this.bindingRecord;
            try {
                // note that the holder != null conditions cause a null return at any part of the reference chain to resolve lhsVal to a
                // null value (i.e. guard against null pointer exceptions):
                while (refNode != null && refNode.next != null && holder != null) {
                    holder = holder.getSObject(refNode.name);
                    refNode = refNode.next;
                }
                refNode = simp.ref.refTail;
                if (holder != null) {
                    lhsVal = holder.get(refNode.name);
                }
            } catch (System.sObjectException e) {
                // HACK: here we try to differentiate between invalid references vs. having a queried sObject that did not select this reference -- there is
                // a better way to do this by checking the reference itself against metadata:
                if (e.getMessage().contains('SOQL')) {
                    SOQLParser.evalErr(refNode.getSrcToken(), 'Reference ' + refNode.getResolvedDescripString() + 
                        ' was not SELECTed in queried binding record (Id=' + bindingRecord + ')');
                } else {
                    SOQLParser.evalErr(refNode.getSrcToken(), 'Reference ' + refNode.getResolvedDescripString() + 
                        ' is invalid for sObject type ' + bindingRecord.getSObjectType() + '::' + holder.getSObjectType());
                }
            }
        }

        // resolve the rhs value:
        SOQLLexer.Token opTok = simp.relOp;
        Integer op = simp.relOp.ttype;
        // note that the evaluator doesn't transform beginsWith/endsWith/contains to LIKE, and only a literal LIKE op needs to 
        // specially handle backslash-escapes of '%' and '_':
        Object rhsVal = simp.val.eval(op == SOQLLexer.KW_LIKE, lhsSoapType.name());
        Boolean negateOp;
        if (op == SOQLLexer.EQUALS || (negateOp = (op == SOQLLexer.NOT_EQUALS))) {
            Boolean eval;
            if (lhsSoapType == Schema.SOAPType.Date) {
                if (lhsVal == null || rhsVal == null || rhsVal instanceof Date) {
                    // intentional fallthrough to apply Apex "==" or "!=" operator...
                } else if (rhsVal instanceof DateTime) {
                    // simply use the date component of the rhs:
                    rhsVal = ((DateTime) rhsVal).date();
                } else if (rhsVal instanceof Date[]) {
                    // ranges are inclusive on both endpoints:
                    Date[] rhsRange = (Date[]) rhsVal;
                    Date lhsDate = (Date) lhsVal;
                    Date rhsLowBound = rhsRange[0];
                    Date rhsHighBound = rhsRange[1];
                    // if both bounds are null, then the operation is undefined; ensure that we always eval to false whether the
                    // op is == or != (pre-negate to counteract a !=):
                    if (rhsLowBound == null && rhsHighBound == null) {
                        eval = op == SOQLLexer.NOT_EQUALS ? true : false;
                    } else {
                        // note that if either bound is null, then we consider the rhs an open interval, and we eval to the result of the
                        // other bound's test:
                        eval = (rhsLowBound == null || lhsDate >= rhsLowBound) && (rhsHighBound == null || lhsDate <= rhsHighBound);
                    }
                // TODO:
                } else {
                    System.assert(false, 'Conversion of ' + rhsVal + ' to Date not yet supported');
                } 
                // TODO: re-enable
                /*else if (rhsVal instanceof DateTime[]) {
                    DateTime[] rhsRange = (DateTime[]) rhsVal;
                    Date lhsDate = (Date) lhsVal;
                    DateTime rhsLowBound = rhsRange[0];
                    DateTime rhsHighBound = rhsRange[1];
                    // if both bounds are null, then the operation is undefined; ensure that we always eval to false whether 
                    // the op is == or != 
                    if (rhsLowBound == null && rhsHighBound == null) {
                        eval = op == SOQLLexer.NOT_EQUALS ? true : false;
                    } else {
                        // note that if either bound is null, then we consider the rhs an open interval, and we eval to the result of the
                        // other bound's test:
                        eval = (rhsLowBound == null || lhsDate >= rhsLowBound.date()) && (rhsHighBound == null || lhsDate <= rhsHighBound.date());
                    }
                } else {
                    SOQLParser.evalErr(opTok, 'Expected a Date right-hand side value to \'' + opTok.lexeme + 
                    	'\' operation; got incompatible value [' + rhsVal + ']');
                }
                */
            } else if (lhsSoapType == Schema.SOAPType.DateTime) {
                if (lhsVal == null || rhsVal == null || rhsVal instanceof DateTime) {
                    // intentional fallthrough to apply Apex "==" operator...
                } else if (rhsVal instanceof Date) {
                    // simply use the date component of the lhs:
                    lhsVal = ((DateTime) lhsVal).date();
                } else if (rhsVal instanceof DateTime[]) {
                    // ranges are inclusive on both endpoints:
                    DateTime[] rhsRange = (DateTime[]) rhsVal;
                    DateTime lhsDate = (DateTime) lhsVal;
                    DateTime rhsLowBound = rhsRange[0];
                    DateTime rhsHighBound = rhsRange[1];
                    // if both bounds are null, then the operation is undefined; ensure that we always eval to false whether the
                    // op is == or != (pre-negate to counteract a !=):
                    if (rhsLowBound == null && rhsHighBound == null) {
                        eval = op == SOQLLexer.NOT_EQUALS ? true : false;
                    } else {
                        // note that if either bound is null, then we consider the rhs an open interval, and we eval to the result of the
                        // other bound's test:
                        eval = (rhsLowBound == null || lhsDate >= rhsLowBound) && (rhsHighBound == null || lhsDate <= rhsHighBound);
                    }
                // TODO:
                } else {
                    System.assert(false, 'Conversion of ' + rhsVal + ' to DateTime not yet supported');
                } 
                // TODO: re-enable
                /*else if (rhsVal instanceof Date[]) {
                    Date[] rhsRange = (Date[]) rhsVal;
                    DateTime lhsDateTime = ((DateTime) lhsVal).date();
                    Date rhsLowBound = rhsRange[0];
                    Date rhsHighBound = rhsRange[1];
                    // if both bounds are null, then the operation is undefined; ensure that we always eval to false whether the
                    // op is == or != (pre-negate to counteract a !=):
                    if (rhsLowBound == null && rhsHighBound == null) {
                        eval = op == SOQLLexer.NOT_EQUALS ? true : false;
                    } else {
                        // note that if either bound is null, then we consider the rhs an open interval, and we eval to the result of the
                        // other bound's test:
                        // treat each endpoint of the date range as a "whole day" from Time00 (start of day) to Time24 (last millisecond of day):
                        eval = (rhsLowBound == null || lhsDateTime >= DateTime.newInstance(rhsLowBound, SOQLParser.Time00)) 
                            && (rhsHighBound == null || lhsDateTime <= DateTime.newInstance(rhsHighBound, SOQLParser.Time24));
                    }
                } else {
                    SOQLParser.evalErr(opTok, 'Expected a DateTime right-hand side value to \'' + opTok.lexeme + 
                    	'\' operation; got incompatible value [' + rhsVal + ']');
                }
                */
            }

            // defer to the Apex "==" op if we haven't already resolved to a boolean value:
            if (eval == null) {
                // TODO: should we normalize things like blank strings, etc?
                simp.eval = op == SOQLLexer.NOT_EQUALS ? lhsVal != rhsVal : lhsVal == rhsVal;
            } else {
                simp.eval = op == SOQLLexer.NOT_EQUALS ? !eval : eval;
            }
        } else if (op == SOQLLexer.LESS_THAN) {
            // note the "== true" is necessary becasue abstractRelCmp returns null for undefined operations; these should always eval to false
            simp.eval = abstractRelCmp(opTok, lhsSoapType, lhsVal, rhsVal, false) == true;
        } else if (op == SOQLLexer.GREATER_THAN) {
            simp.eval = abstractRelCmp(opTok, lhsSoapType, rhsVal, lhsVal, true) == true;
        } else if (op == SOQLLexer.LESS_THAN_EQUALS) {
            // note the "negCmp != null" is necessary becasue abstractRelCmp returns null for undefined operations; these should always eval to false
            Boolean negCmp = abstractRelCmp(opTok, lhsSoapType, rhsVal, lhsVal, true);
            simp.eval = negCmp != null && !negCmp;
        } else if (op == SOQLLexer.GREATER_THAN_EQUALS) {
            Boolean negCmp = abstractRelCmp(opTok, lhsSoapType, lhsVal, rhsVal, false);
            simp.eval = negCmp != null && !negCmp;
        // TODO: reconsider handing of null/blank on lhs/rhs for beginsWith/endsWith/contains operators:
        } else if (op == SOQLLexer.KW_BEGINS_WITH || op == SOQLLexer.KW_STARTS_WITH) {
            simp.eval = lhsVal != null && rhsVal != null && toStr(lhsVal).startsWithIgnoreCase(toStr(rhsVal));
        } else if (op == SOQLLexer.KW_ENDS_WITH) {
            simp.eval = lhsVal != null && rhsVal != null && toStr(lhsVal).endsWithIgnoreCase(toStr(rhsVal));
        } else if (op == SOQLLexer.KW_CONTAINS) {
            simp.eval = lhsVal != null && rhsVal != null && toStr(lhsVal).containsIgnoreCase(toStr(rhsVal));
        // op == KW_NOT is used to specify the "NOT IN" op:
        } else if (op == SOQLLexer.KW_IN || op == SOQLLexer.KW_NOT) {
            // convert a scalar value to an array of 1 element:
            Object[] rhsArray;
            if (rhsVal instanceof Object[]) {
                rhsArray = (Object[]) rhsVal;
            } else if (rhsVal != null) {
                rhsArray = new Object[]{ rhsVal };
            // a null rhs resolves to the empty set:
            } else {
                rhsArray = new Object[]{};
            }
            // if the target (lhs) type is String, then we must normalize the letter case of both the lhs and all rhs elements:
            Boolean setMatch;
            if (lhsSoapType == Schema.SOAPType.String || lhsSoapType == Schema.SOAPType.Id) {
                Integer len = rhsArray.size();
                Set<String> rhsSetLc = new Set<String>();
                for (Integer i=0; i < len; i++) {
                    rhsSetLc.add(toStrLc(rhsArray[i]));
                }
                setMatch = rhsSetLc.contains(toStrLc(lhsVal));
            } else {
                // the Apex Set<Object>'s' hash/equals implementation works well for the remaining primitive types:
                setMatch = new Set<Object>(rhsArray).contains(lhsVal);
            }
            simp.eval = setMatch == (op == SOQLLexer.KW_IN);
        } else if (op == SOQLLexer.KW_INCLUDES || op == SOQLLexer.KW_EXCLUDES) {
            Set<String> lhsPicksLc = new Set<String>();
            String lhsStr = toStr(lhsVal);
            if (lhsStr != null) {
                for (String pick : lhsStr.split(';')) {
                    lhsPicksLc.add(pick.toLowerCase());
                }
                lhsPicksLc.remove('');
            }
            Set<String> rhsPicksLc = new Set<String>();
            if (rhsVal instanceof Object[]) {
                Object[] rhsArray = (Object[]) rhsVal;
                for (Object elmt : rhsArray) {
                    rhsPicksLc.add(toStrLc(elmt));
                }
            // a null rhs resolves to the empty set:
            } else if (rhsVal != null) {
                rhsPicksLc.add(toStrLc(rhsVal));
            }
            rhsPicksLc.remove(null);
            rhsPicksLc.remove('');
            if (op == SOQLLexer.KW_INCLUDES) {
                for (String pickLc : rhsPicksLc) {
                    if (!lhsPicksLc.contains(pickLc)) {
                        simp.eval = false;
                        return false;
                    }
                }
                simp.eval = true;
            } else {
                for (String pickLc : rhsPicksLc) {
                    if (lhsPicksLc.contains(pickLc)) {
                        simp.eval = false;
                        return false;
                    }
                }
                simp.eval = true;
            }
        // TODO: reconsider handing of null/blank on lhs/rhs for LIKE operator:
        } else if (op == SOQLLexer.KW_LIKE) {
            // convert the string value to a regexp pattern:
            String lhsStr = toStr(lhsVal);
            // TODO: for now, this is guaranteed to be a String type value in a valid regexp/pattern format, because we passed 
            // isLikeOpTarget=true when calling simp.val.eval(true). if the rhs value wasn't a string, then an eval error would have
            // been thrown:
            String rhsStr = (String) rhsVal;
            if (String.isBlank(lhsStr) && String.isBlank(rhsStr)) {
            	simp.eval = true;
            } else {
            	// TODO: for now we can assume rhsStr is a valid regexp/pattern string that will not cause a compile error (see above):
            	// !! remember we must make the pattern case-insensitive via the "(?i)" lead flag:
                //System.assert(false, '[' + rhsStr + ']');
                simp.eval = Pattern.compile('(?i)' + rhsStr).matcher(lhsStr ?? '').matches();
            }
        } else {
            SOQLParser.evalErr(simp.relOp, '\'' + simp.relOp.lexeme + '\' operator is not yet supported for dynamic evaluation');
        }

        // TODO: between op

        // cancel further traversal down the abstract syntax tree:
        return false;
    }

    // this method can only be called for a SimpleExpr that holds a nested SimpleExpr:
    public virtual override void afterVisit(SimpleExpr simp) {
        if (simp.nested != null) {
            // simply pull the nested result up:
            simp.eval = simp.nested.eval;
        }
    }

    static final Double NaN = Double.valueOf('NaN');
    static final Double Infinity = Double.valueOf('Infinity');
    static final Double NegInfinity = -Infinity;

    // Abstract Relational Comparison operation - based on the same operation defined in the ECMAScript 5.1 specification. 
    // Returns the boolean result of x < y (x less-than y), or returns null for undefined operations (e.g. 42 < NaN)
    //    if reversed == true, then y is the left-hand side (lhs) and x is the rhs (right-hand side) of the SOQL SimpleExpr
    //    if reversed != true, then x is the left-hand side (lhs) and y is the rhs (right-hand side) of the SOQL SimpleExpr
    // The targetType is derived from the lhs of a SimpleExpr, and thus the lhs value's Apex type is fairly rigidly determined by the
    // targetType. However, there can be some flexibility in the typing of the rhs -- most notably, rhs date formula tokens can
    // resolve to a Date or DateTime range.
    static Boolean abstractRelCmp(SOQLLexer.Token opTok, Schema.SOAPType targetType, Object x, Object y, Boolean reversed) {
        if (targetType == Schema.SOAPType.String || targetType == Schema.SOAPType.Id) {
            // lhs is always the RefExpr side of a SimpleExpr; rhs is always the value (SOQL literal value or bound value):
            String lhs = reversed ? (String) y : (String) x;
            String rhs;
            if (reversed) {
                rhs = String.valueOf(x);
            } else {
                rhs = String.valueOf(y);
            }
            if (lhs == null && rhs == null) {
                // string target type allows { lt, gt } ops to return true when lhs and rhs are both null; for all other types a relational 
                // op applied to two nulls returns undefined:
                return false;
            // nulls first:
            // TODO: make nulls first/last configurable?
            } else if (lhs == null) {
                // string type places nulls first for lt, gt ops (treats a null as an empty string); with all other target types a
                // { lt, gt } op applied to null is undefined:
                return true;
            } else if (rhs == null) {
                // string type places nulls first for lt, gt ops (treats a null as an empty string); with all other target types a 
                // { lt, gt } op applied to null is undefined:
                return false;
            } else {
                // heed the reversed flag to ensure we're always performing x < y on the typed/cast lhs and rhs values:
                // TODO: is the Apex less-than op case-insensitive for String operands? if so then we can remove these toLowerCase() calls:
                return reversed ? rhs.toLowerCase() < lhs.toLowerCase() : lhs.toLowerCase() < rhs.toLowerCase();
            }
        } else if (targetType == Schema.SOAPType.Double || targetType == Schema.SOAPType.Integer) {
            // lhs (from sObject number field) must always be a Decimal, not a Double, so we're guaranteed this cast won't fail:
            Decimal lhs = reversed ? (Decimal) y : (Decimal) x;
            Decimal rhs;
            try {
                if (reversed) {
                    rhs = x == null || x instanceof Decimal && x != NaN ? (Decimal) x : Decimal.valueOf(String.valueOf(x));
                } else {
                    rhs = y == null || y instanceof Decimal && y != NaN ? (Decimal) y : Decimal.valueOf(String.valueOf(y));
                }
            // catch TypeException for special handling of IEEE Double's NaN, Infinity, -Infinity values, which cannot be cast to Decimal:
            // TODO: catch concrete Apex Exception type...
            } catch (Exception e) {
                Object orhs = reversed ? x : y;
                // anything compared with NaN is undefined:
                if (orhs == NaN) {
                    return null;
                } else if (orhs == Infinity) {
                    // rhs[Infinity] < lhs is always false; lhs < rhs[Infinity] is always true:
                    return !reversed;
                } else if (orhs == NegInfinity) {
                    // rhs[-Infinity] < lhs is always true; lhs < rhs[-Infinity] is always false:
                    return reversed;
                // this branch can only be reached if a non-number value is bound to the rhs and prior processing doesn't catch the type
                // discrepancy (is that possible?).
                // TODO: also catch type errors for the other target types, possibly with a big wrapper try/catch...
                } else {
                    SOQLParser.evalErr(opTok, 'Expected a Number right-hand side value to \'' + opTok.lexeme + '\' operator; got incompatibe value [' + rhs + ']');
                }
            }
            // null on either side returns undefined:
            if (lhs == null || rhs == null) {
                return null;
            } else {
                return reversed ? rhs < lhs : lhs < rhs;
            }
        } else if (targetType == Schema.SOAPType.Date) {
            Date lhs = reversed ? (Date) y : (Date) x;
            Object orhs = reversed ? x : y;
            Date rhs;
            if (orhs != null) {
                if (orhs instanceof Date) {
                    rhs = (Date) orhs;
                // When the rhs is a date/datetime range, we must resolve which side of that range matters for the x < y comparison.
                // Ranges are defined to be inclusive on both endpoints.
                } else if (orhs instanceof Date[]) {
                    Date[] range = (Date[]) orhs;
                    rhs = reversed ? range[1] : range[0];
                // TODO: re-enable
                } else { System.assert(false, 'Conversion from ' + orhs + ' to Date not yet implemented'); }
                /*
                else if (orhs instanceof DateTime) {
                    DateTime dt = (DateTime) orhs;
                    rhs = reversed ? toDate(dt, false) : toDate(dt, true);
                } else if (orhs instanceof DateTime[]) {
                    DateTime[] range = (DateTime[]) orhs;
                    rhs = reversed ? toDate(range[1], false) : toDate(range[0], true);
                }
                */
            }
            // null on either side returns undefined:
            if (lhs == null || rhs == null) {
                return null;
            } else {
                return reversed ? rhs < lhs : lhs < rhs;
            }
        } else if (targetType == Schema.SOAPType.DateTime) {
            DateTime lhs = reversed ? (DateTime) y : (DateTime) x;
            Object orhs = reversed ? x : y;
            DateTime rhs;
            if (orhs != null) {
                if (orhs instanceof DateTime) {
                    rhs = (DateTime) orhs;
                // When the rhs is a date/datetime range, we must resolve which side of that range matters for the x < y comparison.
                // Ranges are defined to be inclusive on both endpoints.
                } else if (orhs instanceof DateTime[]) {
                    DateTime[] range = (DateTime[]) orhs;
                    rhs = reversed ? range[1] : range[0];
                // TODO: re-enable
                } else { System.assert(false, 'Conversion from ' + orhs + ' to DateTime not yet implemented'); }
                /*else if (orhs instanceof Date) {
                    Date d = (Date) orhs;
                    rhs = reversed ? toDateTime(d, SOQLParser.Time24) : toDateTime(d, SOQLParser.Time00);
                } else if (orhs instanceof Date[]) {
                    Date[] range = (Date[]) orhs;
                    rhs = reversed ? toDateTime(range[1], SOQLParser.Time24) : toDateTime(range[0], SOQLParser.Time00);
                }
                */
            }
            // null on either side returns undefined:
            if (lhs == null || rhs == null) {
                return null;
            } else {
                return reversed ? rhs < lhs : lhs < rhs;
            }
        } else if (targetType == Schema.SOAPType.Boolean) {
            // null on either side of '<' op returns undefined:
            if (x == null || y == null) {
                return null;
            }
            Integer lhs = reversed ? y == true ? 1 : 0 : x == true ? 1 : 0;
            Integer rhs;
            if (reversed) {
                rhs = x == true ? 1 : 0;
            } else {
                rhs = y == true ? 1 : 0;
            }
            return reversed ? rhs < lhs : lhs < rhs;
        // error on base64binary:
        } else {
            SOQLParser.evalErr(opTok, targetType.name() + ' field cannot be used against a \'' + opTok.lexeme + '\' operator');
            return null;
        }
    }

    static String toStr(Object val) {
        if (val instanceof String) {
            return (String) val;
        } else if (val instanceof sObject) {
            return String.valueOf(((sObject) val).Id);
        } else {
            return String.valueOf(val);
        }
    }

    // returns a lower-case'd string, casting val if necessary:
    static String toStrLc(Object val) {
        if (val instanceof String) {
            return ((String) val).toLowerCase();
        } else if (val instanceof sObject) {
            return String.valueOf(((sObject) val).Id).toLowerCase();
        } else {
            return String.valueOf(val).toLowerCase();
        }
    }

    // TODO: re-enable
    /*
    static Date toDate(DateTime dt, Boolean ceilToNextDay) {
        if (dt == null) {
            return null;
        }
        Date d = dt.date();
        if (ceilToNextDay == true && (dt.hour() > 0 || dt.minute() > 0 || dt.second() > 0 || dt.millisecond() > 0)) {
            return d.addDays(1);
        } else {
            return d;
        }
    }

    static DateTime toDateTime(Date d, Time t) {
        if (d == null) {
            return null;
        }
        return DateTime.newInstance(d, t != null ? t : SOQLParser.Time00);
    }
    */
}