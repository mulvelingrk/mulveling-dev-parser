@isTest
global class SOQLContextTest {

    static SOQLContext SystemContext = new SOQLContext()
        .systemCrudFLS()
        .systemSharing();

    static SOQLContext RestrictedContext;

    @isTest
    private static void testAST() {
        String astTrace = getAST(
            'FROM Account ' + 
            'WHERE (ShippingCity = "Atlanta" OR (ShippingCity = "South Jersey Shore")) AND (NOT (ShippingAddress != "612 Wharf Avenue")) ' + 
            'ORDER BY NAME').show();
        System.assertEquals('AND|OR|=|ShippingCity|"Atlanta"|=|ShippingCity|"South Jersey Shore"|NOT|!=|ShippingAddress|"612 Wharf Avenue"', astTrace);

        astTrace = getAST(
            'FROM Account ' + 
            'WHERE ShippingCity = "Atlanta" OR ShippingCity = "South Jersey Shore" AND NOT ShippingAddress != "612 Wharf \\"Avenue\\"" ' + 
            'ORDER BY NAME').show();
            System.assertEquals('OR|=|ShippingCity|"Atlanta"|AND|=|ShippingCity|"South Jersey Shore"|NOT|!=|ShippingAddress|"612 Wharf \\"Avenue\\""', astTrace);
        
        RestrictedContext = new SOQLContext()
            .systemCrudFLS()
            .systemSharing()
            .addRule(
                new SOQLContext.RestrictedToExactMatches('Account Billing 3 of 4', Schema.Account.SObjectType)
                    .setMinimumMatches(3)
                    .addExactMatchElement('AccountNumber', true)
                    .addExactMatchElement('BillingAddress', true)
                    .addExactMatchElement('BillingCity', false)
                    .addExactMatchElement('BillingPostalCode', false)
                    .addFreestyleElement('BillingState', true, true)
                    .addFreestyleElement('Type', false, false)
            );

        expectRuleFail(
            'FROM Account ' + 
            'WHERE BillingAddress = "612 Wharf Avenue" ' + 
                'AND (AccountNumber = "123" OR (AccountNumber = "456")) ' + 
                'AND BillingPostalCode = "10256"',

            'Match condition "AccountNumber" cannot be nested deeper than a top-level AND condition'
        );

        expectRuleFail(
            'FROM Account ' + 
            'WHERE BillingAddress = "612 Wharf Avenue" ' + 
                'OR AccountNumber = "123" ' + 
                'OR BillingPostalCode = "10256" ' + 
                'OR BillingcCity = "Atlanta" ',

            'OR condition must be nested under a parent AND'
        );

        expectRuleFail(
            'FROM Account ' + 
            'WHERE BillingAddress = "612 Wharf Avenue" ' + 
                'AND AccountNumber LIKE "123%" ' + 
                'AND BillingPostalCode = "10256" ' + 
                'AND BillingCity = "South Jersey Shore" ' + 
                'AND BillingState = "NJ" ',

            'Match condition "AccountNumber" is only allowed "="; got "LIKE"'
        );

        expectRuleFail(
            'FROM Account ' + 
            'WHERE BillingAddress = "612 Wharf Avenue" ' +  // match 1
                'AND AccountNumber = "123" ' + // match 2
                'AND BillingState = "NJ" ' + // freestyle
                'AND Type = "Partner" ', // freestyle

            'Expected at least 3 match conditions; got 2'
        );

        expectRuleFail(
            'FROM Contact ' + // wrong Object
            'WHERE (BillingAddress = "612 Wharf Avenue" ' + // match 1
                'AND ((AccountNumber = "123")) ' + // match 2
                'AND BillingPostalCode = "10256")', // match 3
            
            'Illegal "FROM Contact" clause; only "FROM Account" is allowed'
        );

        expectRuleFail(
            'FROM Account ' +
            'WHERE (BillingAddress = "612 Wharf Avenue" ' + // match 1
                'AND ((AccountNumber = "123")) ' + // match 2
                'AND BillingPostalCode = "10256") ' +  // match 3
            'ORDER BY AccountNumber ', // illegal ORDER BY

            'ORDER BY clause is not allowed'
        );

        expectRuleFail(
            'FROM Account ' +
            'WHERE AccountNumber = "123" ' +
                'AND BillingPostalCode = "10256" ' +
                'AND (BillingAddress = "612 Wharf Avenue" OR Type = "Competitor") ', // OR violation

            'Match condition "BillingAddress" cannot be nested deeper than a top-level AND condition'
        );

        expectRuleFail(
            'FROM Account ' +
            'WHERE BillingAddress = "612 Wharf Avenue" ' + 
                'AND AccountNumber = "123" ' +
                'AND BillingPostalCode = "10256" ' +
                'AND (BillingAddress = "5785 Redcoat Run") ', // double-match violation

            'Match condition "BillingAddress" cannot be used more than once'
        );

        expectRuleFail(
            'FROM Account ' +
            'WHERE AccountNumber = "123" ' +
                'AND BillingPostalCode = "10256" ' +
                'AND NOT BillingAddress = "5785 Redcoat Run" ', // NOT violation

            'Match condition "BillingAddress" cannot be nested deeper than a top-level AND condition'
        );

        expectRuleFail(
            'FROM Account ' +
            'WHERE BillingAddress = "612 Wharf Avenue" ' + 
                'AND BillingCity = "Stone Mountain" ' +
                'AND BillingPostalCode = "30087" ' +
                'AND Type = "Competitor" ',

            'Required match condition "AccountNumber" is not present'
        );

        // TODO: Oops, ParseException I need to look into. SOQL does allow '=' on List arguments, 
        // at least in some cases, and so should SOQLParser...
        /*expectRuleFail(
            'FROM Account ' +
            'WHERE AccountNumber = ("123", "456") ' + 
                'AND BillingAddress = "612 Wharf Avenue" ' + 
                'AND BillingCity = "Stone Mountain" ' +
                'AND BillingPostalCode = "30087" ',

            'Match condition "AccountNumber" is only allowed simple match values; got list value'
        );*/

        expectRuleFail(
            'FROM Account ' +
            'WHERE AccountNumber = :foo ' + 
                'AND BillingAddress = "612 Wharf Avenue" ' + 
                'AND BillingCity = "Stone Mountain" ' +
                'AND BillingPostalCode = "30087" ',

            'Match condition "AccountNumber" is only allowed literal match values; got bind parameter ":foo"'
        );

        // Pass!
        expectRulePass(
            'FROM Account ' + 
            'WHERE (BillingAddress = "612 Wharf Avenue" ' + // match 1
                'AND ((AccountNumber = "123")) ' + // match 2
                'AND BillingPostalCode = "10256")' // match 3
        );

        // Pass!
        expectRulePass(
            'FROM Account ' + 
            'WHERE BillingAddress = "612 Wharf Avenue" ' + // match 1
                'AND ((AccountNumber = "123")) ' + // match 2
                'AND BillingPostalCode = "10256"' + // match 3
                'AND (BillingState = "GA" OR BillingState beginsWith "A")' // freestyle element, allows nesting and any op
        );

        expectRuleFail(
            'FROM Account ' + 
            'WHERE BillingAddress = "612 Wharf Avenue" ' + // match 1
                'AND ((AccountNumber = "123")) ' + // match 2
                'AND BillingPostalCode = "10256"' + // match 3
                'AND (Type = "Partner" OR Type beginsWith "C")', // freestyle element, dose NOT allow nesting

            'Freestyle condition "Type" cannot be nested deeper than a top-level AND condition'
        );

        // TODO: This fails becasue the match conditions are nested in an AND|AND - but should that be OK?
        /*// Pass!
        expectRulePass(
            'FROM Account ' + 
            'WHERE (BillingAddress = "612 Wharf Avenue" ' + // match 1
                'AND ((AccountNumber = "123")) ' + // match 2
                'AND BillingPostalCode = "10256")' + // match 3
                'AND (BillingState = "GA" OR BillingState beginsWith "A")' // freestyle element, allows nesting and any op
        );*/
        
    }

    static void expectRuleFail(String query, String expectedMessage) {
        Assert.isNotNull(RestrictedContext, 'RestrictedContext has not been initialized');
        SOQLContext.RestrictedSearch rule;
        switch on RestrictedContext.searchRules.size() {
            when 0 {
                Assert.fail('RestrictedContext has no rules; one must be specified');
            }
            when 1 {
                rule = RestrictedContext.searchRules[0];
            }
            when else {
                Assert.fail('RestrictedContext has multiple rules; one must be specified');
            }
        }
        expectRuleFail(query, rule.name, expectedMessage);
    }

    static void expectRuleFail(String query, String ruleName, String expectedMessage) {
        Assert.isNotNull(RestrictedContext, 'Restricted Search Context has not been initialized');
        expectedMessage = 'Restricted Search Violation [' + ruleName + ']: ' + expectedMessage;
        try { 
            RestrictedContext.validate(query);
            Assert.fail('Unexpected Rule Pass; Expected Fail [' + expectedMessage + ']');
        } catch(SOQLContext.RestrictedSearchException e) {
            Assert.isTrue(expectedMessage == e.getMessage(), 
                'Unexpected Rule Fail [' + e.getMessage() + ']; Expected Different Fail [' + expectedMessage + ']');
        }
    }

    static SOQLParser.SOQL expectRulePass(String query) {
        Assert.isNotNull(RestrictedContext, 'Restricted Search Context has not been initialized');
        SOQLParser.SOQL soql;
        try { 
            soql = RestrictedContext.validate(query);
        } catch(SOQLContext.RestrictedSearchException e) {
            Assert.fail('Unexpected Rule Fail [' + e.getMessage() + ']; Expected Pass');
        }
        return soql;
    }

    static ASTWalk getAST(String query) {
        SOQLParser.SOQL soql = SystemContext.validate(query);
        ASTWalk walker = new ASTWalk();
        soql.whereCond.traverse(walker);
        return walker;
    }

    global class ASTWalk extends SOQLParser.ASTVisitor {
        String[] stack = new String[]{};

        global override void onStart(ASTCond root) {
            this.stack = new String[]{};
        }

        global override void onCond(ASTCond cond) {
            if (cond.isAnd()) {
                stack.add('AND');
            } else if (cond.isOr()) {
                stack.add('OR');
            } else if (cond.isNot()) {
                stack.add('NOT');
            } else if (cond.isGroup()) {
                stack.add('()');
            } else if (cond.isSimple()) {
                stack.add(((ASTSimpleCond) cond).op.lexeme);
            }
        }

        global override void onLeaveCond(ASTCond cond) {}
        global override void onValue(ASTValue val) {
            if (val.scalar != null) {
                stack.add(val.scalar.loc.lexeme);
            } else {
                stack.add('<LIST_VALUE>');
            }
        }
        global override void onReference(ASTReference ref) {
            stack.add(ref.getBestPath());
        }
        global override void onFinish(ASTCond root) {}

        String show() {
            return String.join(stack, '|');
        }
    }
}