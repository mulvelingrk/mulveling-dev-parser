public class ComponentRelationshipTriggerHandler {

    public static void handle() {
        Map<Id, RecordTypeInfo> typeMap = Schema.Component_Relationship__c.sObjectType.getDescribe().getRecordTypeInfosById();
        Set<Id> compScope = new Set<Id>();
        Set<Id> compRelScope = new Set<Id>();
        for (Component_Relationship__c rel : (Component_Relationship__c []) Trigger.new) {
            RecordTypeInfo typeInfo = typeMap.get(rel.RecordTypeId);
            String typeName = typeInfo.getDeveloperName();
            if (typeName == 'Tube_Component') {
                rel.Src__c = rel.Tube__c;
                rel.Dest__c = rel.Tubed_Component__c;
                compScope.add(rel.Tube__c);
                compScope.add(rel.Tubed_Component__c);
            } else if (typeName == 'Cartridge_Phono') {
                compRelScope.add(rel.Table_Cartridge__c);
                rel.Dest__c = rel.Phono_Stage__c;
                rel.Intermediate__c = rel.SUT__c;
                rel.Signal_Cable__c = rel.SUT_Cable__c;
                compScope.add(rel.Phono_Stage__c);
                compScope.add(rel.SUT__c);
                compScope.add(rel.SUT_Cable__c);
            } else if (typeName == 'Table_Cartridge') {
                rel.Src__c = rel.Table__c;
                rel.Dest__c = rel.Cartridge__c;
                rel.Intermediate__c = rel.Tonearm__c;
                rel.Signal_Cable__c = rel.Tonearm_Cable__c;
                compScope.add(rel.Table__c);
                compScope.add(rel.Cartridge__c);
                compScope.add(rel.Tonearm__c);
                compScope.add(rel.Armboard__c);
                compScope.add(rel.Tonearm_Cable__c);
                compScope.add(rel.Headshell__c);
                compScope.add(rel.Headshell_Leads__c);
            } else if (typeName == 'Component_Component') {
                rel.Src__c = rel.Upstream__c;
                rel.Dest__c = rel.Downstream__c;
                rel.Signal_Cable__c = rel.Interconnect__c;
                rel.Intermediate__c = rel.Interconnect__c;
                compScope.add(rel.Upstream__c);
                compScope.add(rel.Downstream__c);
                compScope.add(rel.Interconnect__c);
            } else if (typeName == 'Accessory_Component') {
                rel.Src__c = rel.Accessory__c;
                rel.Dest__c = rel.Accessorized_Component__c;
                compScope.add(rel.Accessory__c);
                compScope.add(rel.Accessorized_Component__c);
            } else if (typeName == 'Amp_Speaker') {
                rel.Src__c = rel.Amp__c;
                rel.Dest__c = rel.Speakers__c;
                compScope.add(rel.Amp__c);
                compScope.add(rel.Speakers__c);
                Id[] cables = new Id[]{ rel.Full_Range_Cable__c, rel.Treble_Cable__c, rel.Bass_Cable__c };
                compScope.addAll(cables);
                for (Id c : cables) {
                    if (c != null) {
                        rel.Intermediate__c = c;
                        rel.Signal_Cable__c = c;
                        break;
                    }
                }
            }
        }
        Map<Id, Component_Relationship__c> compRelMap = new Map<Id, Component_Relationship__c>([ 
            SELECT Name, Table__c, Table_Cartridge__r.Cartridge__c, Cartridge__c, Tonearm__c, Tonearm_Cable__c, Armboard__c, Headshell__c, Headshell_Leads__c
            FROM Component_Relationship__c
            WHERE Id IN :(compRelScope) ]);
        
        for (Component_Relationship__c compRel : (Component_Relationship__c []) compRelMap.values()) {
            compScope.addAll(new Id[]{ compRel.Table__c, compRel.Cartridge__c, compRel.Tonearm__c, compRel.Tonearm_Cable__c, 
                compRel.Armboard__c, compRel.Headshell__c, compRel.Headshell_Leads__c });
            if (compRel.Table_Cartridge__r != null) {
                compScope.add(compRel.Table_Cartridge__r.Cartridge__c);
            }
        }
        compScope.remove(null);
        Map<Id, Audio_Component__c> compMap = new Map<Id, Audio_Component__c>();
        for (System_Component__c sc : [ 
                SELECT Audio_Component__r.Model__c, Audio_Component__r.Manufacturer__c 
                FROM System_Component__c 
                WHERE Id IN :(compScope) ]) {
            compMap.put(sc.Id, sc.Audio_Component__r);
        }
        
        for (Component_Relationship__c rel : (Component_Relationship__c []) Trigger.new) {
            RecordTypeInfo typeInfo = typeMap.get(rel.RecordTypeId);
            String typeName = typeInfo.getDeveloperName();
            String[] nameParts;
            switch on typeName {
                when 'Tube_Component' {
                    // "[RCA 12AX7] In [VAC Renaissance SE]"
                    //nameParts = new String(){ rel. }
                    Audio_Component__c tube = compMap.get(rel.Tube__c);
                    Audio_Component__c tubedComp = compMap.get(rel.Tubed_Component__c);
                    System.debug(rel);
                    System.debug(compMap);
                    System.debug(tube);
                    rel.Name = substr(String.format('[{0}] In [{1}]', new String[]{
                        String.join(new String[]{ tube.Manufacturer__c, tube.Model__c }, ' '), 
                        String.join(new String[]{ tubedComp.Manufacturer__c, tubedComp.Model__c }, ' ')
                    }), 80);
                }
                when 'Amp_Speaker' {
                    // "[Phison A2.120 SE] Drives [Tannoy Canterbury GR] Full-Range"
                    Audio_Component__c amp = compMap.get(rel.Amp__c);
                    Audio_Component__c speak = compMap.get(rel.Speakers__c);
                    rel.Name = substr(String.format('[{0}] Drives [{1}] {2}', new String[]{
                        String.join(new String[]{ amp.Manufacturer__c, amp.Model__c }, ' '), 
                        String.join(new String[]{ speak.Manufacturer__c, speak .Model__c }, ' '),
                        rel.Amp_Configuration__c
                    }), 80);
                }
                when 'Table_Cartridge' {
                    // "[Koetsu Blue Lace] On [FR64S] / [Master Innovation]"
                    Audio_Component__c cart = compMap.get(rel.Cartridge__c);
                    Audio_Component__c arm = compMap.get(rel.Tonearm__c);
                    Audio_Component__c table = compMap.get(rel.Table__c);
                    rel.Name = substr(String.format('[{0}] On [{1}] / [{2}]', new String[]{
                        String.join(new String[]{ cart.Manufacturer__c, cart.Model__c }, ' '), 
                        arm.Model__c,
                        table.Model__c
                    }), 80);
                }
                when 'Cartridge_Phono' {
                    // "[Koetsu Blue Lace] / [FR64S] Into [EAR MC-3] And [Reference 3SE]"
                    Id cartSysCompId = compRelMap.get(rel.Table_Cartridge__c)?.Cartridge__c;
                    Audio_Component__c arm = compMap.get(compRelMap.get(rel.Table_Cartridge__c).Tonearm__c);
                    Audio_Component__c cart = compMap.get(cartSysCompId); //compMap.get(rel.Cartridge__c);
                    Audio_Component__c sut = compMap.get(rel.SUT__c);
                    Audio_Component__c phono = compMap.get(rel.Phono_Stage__c);
                    rel.Src__c = cartSysCompId;
                    if (sut != null) { 
                        rel.Name = substr(String.format('[{0}] / [{1}] Into [{2}] And [{3}]', new String[]{
                            String.join(new String[]{ cart?.Manufacturer__c, cart?.Model__c }, ' '), 
                            arm.Model__c,
                            String.join(new String[]{ sut?.Manufacturer__c, sut?.Model__c }, ' '),
                            phono.Model__c
                        }), 80);
                    } else { 
                        rel.Name = substr(String.format('[{0}] / [{1}] Into [{2}]', new String[]{
                            String.join(new String[]{ cart?.Manufacturer__c, cart?.Model__c }, ' '), 
                            arm.Model__c,
                            phono.Model__c
                        }), 80);
                    }
                }
                when 'Component_Component' {
                    // "[Koetsu Blue Lace] On [FR64S] / [Master Innovation]"
                    Audio_Component__c upstream = compMap.get(rel.Upstream__c);
                    Audio_Component__c downstream = compMap.get(rel.Downstream__c);
                    rel.Name = substr(String.format('[{0}] Into [{1}]', new String[]{
                        String.join(new String[]{ upstream.Manufacturer__c, upstream.Model__c }, ' '), 
                        String.join(new String[]{ downstream.Manufacturer__c, downstream.Model__c }, ' ')
                    }), 80);
                }
                when 'Accessory_Component' {
                    // "[Koetsu Blue Lace] On [FR64S] / [Master Innovation]"
                    Audio_Component__c accessory = compMap.get(rel.Accessory__c);
                    Audio_Component__c accesorized = compMap.get(rel.Accessorized_Component__c);
                    rel.Name = substr(String.format('[{0}] For [{1}]', new String[]{
                        String.join(new String[]{ accessory .Manufacturer__c, accessory.Model__c }, ' '), 
                        String.join(new String[]{ accesorized .Manufacturer__c, accesorized .Model__c }, ' ')
                    }), 80);
                }
            }
        }
    }

    static String substr(String val, Integer len) {
        return val != null && val.length() > 80 ? val.substring(0, len) : val;
    }
}