public class TestCallouts {
    public static String pingMessage() {
        XMLStreamWriter x = new XMLStreamWriter();
        x.writeStartDocument('UTF-8', '1.0');
        x.writeStartElement('env', 'Envelope', 'http://schemas.xmlsoap.org/soap/envelope/');
        x.writeNamespace('env', 'http://schemas.xmlsoap.org/soap/envelope/');
        x.writeNamespace('xsd', 'http://www.w3.org/2001/XMLSchema');
        x.writeNamespace('xsi', 'http://www.w3.org/2001/XMLSchema-instance');
            x.writeStartElement('env', 'Header', 'http://schemas.xmlsoap.org/soap/envelope/');
                x.writeStartElement(null, 'Security', null);
                x.writeDefaultNamespace('http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd');
                    x.writeStartElement(null, 'UsernameToken', null);
                    x.writeNamespace('wsu', 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd');
                    x.writeAttribute('wsu', 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd', 'Id', 'UsernameToken-2');

                        x.writeStartElement(null, 'Username', null);
                        x.writeCharacters('riskonnect_test');
                        x.writeEndElement();
                        x.writeStartElement(null, 'Password', null);
                        x.writeCharacters('cbe0f362-4165-494f-986c-4b57d8f65b0b');
                        x.writeEndElement();

                    x.writeEndElement();
                x.writeEndElement();
            x.writeEndElement();

            x.writeStartElement('env', 'Body', 'http://schemas.xmlsoap.org/soap/envelope/');
                x.writeStartElement('m', 'ping', 'http://schema.lds.org/riskonnect-service/v1_0');
                x.writeNamespace('m', 'http://schema.lds.org/riskonnect-service/v1_0');
                x.writeEndElement();
            x.writeEndElement();

        x.writeEndElement();
        System.debug(x.getXmlString());
        return x.getXmlString();
    }

    public static void ping() {

        HttpRequest req = new HttpRequest();
        HttpResponse res = new HttpResponse();
        Http http = new Http();

        req.setEndpoint('https://rmis-beta.lds.org/ws/riskonnect-services/v1.0/Services/soap/RiskconnectService/ping');
        req.setMethod('POST');
        req.setHeader('SOAPAction', '');
        req.setHeader('Accept', 'text/xml');
        req.setHeader('User-Agent', 'SFDC-Callout/36.0 SFDC_STACK_DEPTH=1');
        req.setHeader('Content-Type', 'text/xml');
        req.setHeader('charset', 'UTF-8');

//14:21:49.1 (262123926)|CALLOUT_REQUEST|[484]|ping:[apex_schema_type_info=(http://schema.lds.org/riskonnect-service/v1_0, false, false), field_order_type_info=()]::SOAPAction="" Accept=text/xml User-Agent=SFDC-Callout/36.0 SFDC_STACK_DEPTH=1 Content-Type=text/xml; charset=UTF-8 


        req.setBody(pingMessage());
        //req.setBody('name='+EncodingUtil.urlEncode(name, 'UTF-8')+'&city='+EncodingUtil.urlEncode(city, 'UTF-8'));
        //req.setCompressed(true); // otherwise we hit a limit of 32000

//        try {
            res = http.send(req);
            System.debug(res.getBody());
//        } catch(System.CalloutException e) {
//            System.debug('Callout error: '+ e);
//            System.debug(res.toString());
//        }

    }
}

/*
<?xml version="1.0" encoding="UTF-8"?>
<env:Envelope 
        xmlns:env="http://schemas.xmlsoap.org/soap/envelope/" 
        xmlns:xsd="http://www.w3.org/2001/XMLSchema" 
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <env:Header>
        <Security xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
            <UsernameToken xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="UsernameToken-2">
                <Username>riskonnect_test</Username>
                <Password>cbe0f362-4165-494f-986c-4b57d8f65b0b</Password>
            </UsernameToken>
        </Security>
    </env:Header>
    <env:Body>
        <m:ping xmlns:m="http://schema.lds.org/riskonnect-service/v1_0"></m:ping>
    </env:Body>
</env:Envelope>
*/

/*
<?xml version="1.0" encoding="UTF-8"?>
<env:Envelope 
        xmlns:env="http://schemas.xmlsoap.org/soap/envelope/" 
        xmlns:xsd="http://www.w3.org/2001/XMLSchema" 
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <env:Header>
        <Security xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
            <UsernameToken xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" wsu:Id="UsernameToken-2">
                <Username>riskonnect_test</Username>
                <Password>cbe0f362-4165-494f-986c-4b57d8f65b0b</Password>
            </UsernameToken>
        </Security>
    </env:Header>
    <env:Body>
        <m:ping xmlns:m="http://schema.lds.org/riskonnect-service/v1_0" />
    </env:Body>
</env:Envelope>
*/