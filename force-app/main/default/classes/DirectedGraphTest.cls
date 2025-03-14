/*
 * Mike Ulveling
 */
@isTest
private class DirectedGraphTest {
    
    @IsTest
    static void buildPathsByCodes() {
        Harness testSet = new Harness();
        
        DirectedGraph graph = new DirectedGraph.Builder(Schema.Test_Hier__c.sObjectType, 'Code__c', 'Parent_Code__c')
            .toGraph(new sObject[]{ 
                    testSet.n('01'),
                    testSet.n('04'),
                    testSet.n('06'),
                    testSet.n('07'), 
                    testSet.n('08'),
                    testSet.n('09'),
                    testSet.n('20'),
                    testSet.n('A'),
                    testSet.n('I')  
                }, 1);

        Map<Id, DirectedGraph.Path> paths = graph.getStartPaths();
        final String sep = ' 🡒 ';
        DirectedGraph.Path p = paths.get(testSet.n('01').Id);
        Assert.areEqual('01 🡒 A 🡒 I 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('04').Id);
        Assert.areEqual('04 🡒 C 🡒 II 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('06').Id);
        Assert.areEqual('06 🡒 C 🡒 II 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('07').Id);
        Assert.areEqual('07 🡒 D 🡒 III 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('08').Id);
        Assert.areEqual('08 🡒 E 🡒 III 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('09').Id);
        Assert.areEqual('09 🡒 E 🡒 III 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('20').Id);
        Assert.areEqual('20 🡒 F 🡒 III 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('I').Id);
        Assert.areEqual('I 🡒 R', p.ser(sep));
        p = paths.get(testSet.n('A').Id);
        Assert.areEqual('A 🡒 I 🡒 R', p.ser(sep));
    }

    @isTest
    static void testCycleDetection() {
        Harness testSet = new Harness();
        // Root now points to a leaf node!
        Test_Hier__c root = testSet.n('R');
        root.Parent_Code__c = '20';
        update root;
        
        DirectedGraph graph = new DirectedGraph.Builder(Schema.Test_Hier__c.sObjectType, 'Code__c', 'Parent_Code__c')
            .toGraph(new sObject[]{ 
                    testSet.n('01'),
                    testSet.n('04'),
                    testSet.n('06'),
                    testSet.n('07'), 
                    testSet.n('08'),
                    testSet.n('09'),
                    testSet.n('20'),
                    testSet.n('A'),
                    testSet.n('I')  
                }, 1);

        Map<Id, DirectedGraph.Path> paths = graph.getStartPaths();
        final String sep = ' 🡒 ';
        DirectedGraph.Path p = paths.get(testSet.n('01').Id);
        Assert.areEqual('01 🡒 A 🡒 I 🡒 R 🡒 20 🡒 F 🡒 III 🡒 R 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('04').Id);
        Assert.areEqual('04 🡒 C 🡒 II 🡒 R 🡒 20 🡒 F 🡒 III 🡒 R 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('06').Id);
        Assert.areEqual('06 🡒 C 🡒 II 🡒 R 🡒 20 🡒 F 🡒 III 🡒 R 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('07').Id);
        Assert.areEqual('07 🡒 D 🡒 III 🡒 R 🡒 20 🡒 F 🡒 III 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('08').Id);
        Assert.areEqual('08 🡒 E 🡒 III 🡒 R 🡒 20 🡒 F 🡒 III 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('09').Id);
        Assert.areEqual('09 🡒 E 🡒 III 🡒 R 🡒 20 🡒 F 🡒 III 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('20').Id);
        Assert.areEqual('20 🡒 F 🡒 III 🡒 R 🡒 20 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('I').Id);
        Assert.areEqual('I 🡒 R 🡒 20 🡒 F 🡒 III 🡒 R 🡒 {cyclic}', p.ser(sep));
        p = paths.get(testSet.n('A').Id);
        Assert.areEqual('A 🡒 I 🡒 R 🡒 20 🡒 F 🡒 III 🡒 R 🡒 {cyclic}', p.ser(sep));
    }

    @IsTest
    static void buildPathsByLkp() {
        Harness testSet = new Harness();

        Map<Id, Test_Hier__c> hiersMap = new Map<Id, Test_Hier__c>([ SELECT Code__c, Parent_Code__c FROM Test_Hier__c ]);
        DirectedGraph graph = new DirectedGraph.Builder(Schema.Test_Hier__c.sObjectType, 'Code__c', 'Parent_Code__c')
            .toGraph(hiersMap.values(), 1);
        
        Map<Id, DirectedGraph.Path> pathsMap = graph.getStartPaths();
        for (Id nodeId : pathsMap.keySet()) {
            DirectedGraph.Path path = pathsMap.get(nodeId);
            // A path's "start" is the Node corresponding to the nodeId (Test_Hier__c.Id) it was mapped under:
            DirectedGraph.Node start = path.start;
            DirectedGraph.Node parent = start.next;
            if (parent != null) {
                Test_Hier__c nodeData = hiersMap.get(nodeId);
                nodeData.Parent__c = parent.data.Id;
                if (!path.cyclic) {
                    Integer level = path.acyclicLength;
                    nodeData.Level__c = level;
                    for (; --level >= 1;) {
                        nodeData.put('Parent_Level_' + level + '__c', parent.data.Id);
                        parent = parent.next;
                    }
                }
            }
        }
        update hiersMap.values();
        
        graph = new DirectedGraph.Builder(Schema.Test_Hier__c.sObjectType, 'Parent__c')
            .addSelects(new String[]{ 
                    'Parent_Code__c', 'Level__c', 'Parent_Level_1__c', 'Parent_Level_2__c', 
                    'Parent_Level_3__c', 'Parent_Level_4__c', 'Parent_Level_5__c' })
                .toGraph(hiersMap.keySet());
        pathsMap = graph.getStartPaths();

        DirectedGraph.Path p = pathsMap.get(testSet.n('07').Id);
        Test_Hier__c pData = (Test_Hier__c) p.start.data;

        Assert.areEqual(4, pData.Level__c);
        Assert.areEqual(testSet.n('D').Id, pData.Parent__c);
        Assert.areEqual(testSet.n('R').Id, pData.Parent_Level_1__c);
        Assert.areEqual(testSet.n('III').Id, pData.Parent_Level_2__c);
        Assert.areEqual(testSet.n('D').Id, pData.Parent_Level_3__c);
        Assert.isNull(pData.Parent_Level_4__c);

        Assert.areEqual(1, graph.queryCount);
    }

    @IsTest
    static void testHierFlatten() {
        Harness harness = new Harness();

        HierFlatten flatten = HierFlatten.TargetSelf(Schema.Test_Hier__c.sObjectType, 'Code__c', 'Parent_Code__c')
            .fillSelfLookup('Parent__c')
            .fillLevelNumber('Level__c')
            .fillAncestorLookupsFrom(8, 'Parent_Level_{0}__c');
        
        flatten.go(SOQLContext.newSystemMode().query('SELECT * FROM Test_Hier__c'));
        harness.load();

        Test_Hier__c n_07 = harness.n('07');
        Assert.areEqual(4, n_07.Level__c);
        Assert.areEqual(harness.n('D').Id, n_07.Parent__c);
        Assert.areEqual(harness.n('R').Id, n_07.Parent_Level_1__c);
        Assert.areEqual(harness.n('III').Id, n_07.Parent_Level_2__c);
        Assert.areEqual(harness.n('D').Id, n_07.Parent_Level_3__c);
        Assert.isNull(n_07.Parent_Level_4__c);
    }

    class Harness {
        Test_Hier__c[] newNodes;
        Map<String, Test_Hier__c> nodesByCode = new Map<String, Test_Hier__c>();

        Harness() {
            init();
        }

        Harness load() {
            this.loadHiers();
            return this;
        }

        Harness loadHiers() {
            this.nodesByCode = new Map<String, Test_Hier__c>();
            for (Test_Hier__c hier : (Test_Hier__c[]) SOQLContext.newSystemMode()
                    .query('SELECT * FROM Test_Hier__c')) {
                nodesByCode.put(hier.Code__c, hier);
            }
            return this;
        }

        Harness init() {
            initHiers();
            return this;
        }

        Test_Hier__c n(String code) {
            Test_Hier__c node = this.nodesByCode.get(code);
            if (node == null) {
                Assert.fail(String.format('Node [{0}] does not exist', new String[]{ code }));
            }
            return node;
        }

        void initHiers() {
            nn('R', null);
            saveHiers();
            nn('I', 'R');
            nn('II', 'R');
            nn('III', 'R');
            saveHiers();
            nn('A', 'I');
            nn('B', 'I');
            nn('C', 'II');
            nn('D', 'III');
            nn('E', 'III');
            nn('F', 'III');
            saveHiers();
            nn('01', 'A');
            nn('02', 'A');
            nn('03', 'B');
            nn('04', 'C');
            nn('05', 'C');
            nn('06', 'C');
            nn('07', 'D');
            nn('08', 'E');
            nn('09', 'E');
            nn('10', 'F');
            nn('11', 'F');
            nn('12', 'F');
            nn('13', 'F');
            nn('14', 'F');
            nn('15', 'F');
            nn('16', 'F');
            nn('17', 'F');
            nn('18', 'F');
            nn('19', 'F');
            nn('20', 'F');
            saveHiers();
        }

        // nn stands for "new node":
        Test_Hier__c nn(String code, String parentCode) {
            return nn(code, parentCode, false);
        }

        // nn stands for "new node":
        Test_Hier__c nn(String code, String parentCode, Boolean resolveParent) {
            if (this.newNodes == null) {
                this.newNodes = new Test_Hier__c[]{};
            }
            Test_Hier__c newNode = new Test_Hier__c(Name = code, Code__c = code, Parent_Code__c = parentCode);
            this.newNodes.add(newNode);
            Test_Hier__c clash = this.nodesByCode.put(code, newNode);
            if (clash != null) {
                Assert.fail(String.format('Node with code [{0}] was previously created)', new String[]{ code }));
            }
            // try to resolve the parent, if this was flagged:
            if (resolveParent == true && parentCode != null) {
                Test_Hier__c parentNode = this.nodesByCode.get(parentCode);
                if (parentNode == null) {
                    Assert.fail(String.format(
                        'Node [{0}] cannot resolve parent node [{1}]', new String[]{ code, parentCode }));
                }
                if (parentNode.Id == null) {
                    Assert.fail(String.format(
                        'Node [{0}] cannot resolve parent node [{1}] before the latter has been inserted', new String[]{ code, parentCode }));
                }
                newNode.Parent__c = parentNode.Id;
            }
            return newNode;
        }

        void saveHiers() {
            if (this.newNodes != null) {
                insert this.newNodes;
                this.newNodes = null;
            }
        }
        
    }
}