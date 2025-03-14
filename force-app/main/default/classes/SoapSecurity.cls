/*
 * Provides functionality for providing UsernameToken WS-Security to a service callout.
 * 
 * To use, add the following lines to the [service]Port class generated by the WSDL to Apex tool:
 *
 * private SoapSecurity.Security Security = SoapSecurity.getUsernameTokenSecurity([username], [password]);
 * private String Security_hns = SoapSecurity.getSoapHeaderNamespace();
 */
public class SoapSecurity {
    //WS-Security namespaces
    public static final String wsseNs = 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd';
    public static final String wsuNs = 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd';

    /*
     * Returns the String required for the soap header namespace variable
     */
    public static String getSoapHeaderNamespace() {
        return 'Security=' + SoapSecurity.wsseNs;
    }

    /*
     * Returns a Security object populated with username and a plaintext password.
     */
    public static SoapSecurity.Security getUsernameTokenSecurity(String user, String password) {
        SoapSecurity.Security s = new SoapSecurity.Security();
        s.UsernameToken = new SoapSecurity.UsernameToken();
        s.UsernameToken.Username = user;
        s.UsernameToken.Password = password;
        return s;
    }
    
    /*
     * Defines the UsernameToken object that is used to generate the corresponding soap header element.
     * Currently only plaintext passwords are supported (hopefully this will change in a later version).
     * Note that the Id and wsu variables are something of a hack to populate additional  security meta-data
     */
    public class UsernameToken {
        private String Id = 'UsernameToken-2';
        private String wsu = SoapSecurity.wsuNs;
        public String Username;
        public String Password;
        private String[] Id_att_info = new String[] {'wsu:Id'};
        private String[] wsu_att_info = new String[] {'xmlns:wsu'};
        private String[] Username_type_info = new String[] {'Username','http://www.w3.org/2001/XMLSchema','string','1','1','false'};
        private String[] Password_type_info = new String[] {'Password',SoapSecurity.wsseNs,'string','1','1','false'};
        private String[] apex_schema_type_info = new String[] {SoapSecurity.wsseNs,'true','false'};
        private String[] field_order_type_info = new String[] {'Username','Password'};
    }
    
    /*
     * Defines the Security object that is used to generate the WS-Security Soap Header element.
     * Currently only supports UsernameToken with a plaintext password.
     */
    public class Security {
        public SoapSecurity.UsernameToken UsernameToken;
        private String[] UsernameToken_type_info = new String[] {'UsernameToken',SoapSecurity.wsseNs,'UsernameToken','1','1','false'};
        private String[] apex_schema_type_info = new String[] {SoapSecurity.wsseNs,'true','false'};
        private String[] field_order_type_info = new String[] {'UsernameToken'};
    }

}