@RestResource(urlMapping='/ContactColor/v1/*')
global with sharing class CustomContactResource {
	@HttpPatch
	global static String patchContact() {
		RestRequest req = RestContext.request;
		RestResponse res = RestContext.response;
		String reqName = req.requestURI.substring(req.requestURI.lastIndexOf('/') + 1);
		Id reqId;
		try {
			reqId = (Id) reqName;
			if (reqId != null && reqId.getSObjectType() != Schema.Contact.sObjectType) {
				reqId = null; // not usable if not a Contact Id
			}
		} catch (Exception notAnId) {} // ignore

		Contact[] matches = new Contact[]{};
		if (reqId != null) {
			matches = [ SELECT Id FROM Contact WHERE Id = :reqId ];
		}
		if (matches.isEmpty()) {
			matches = [ SELECT Id FROM Contact WHERE Name = :reqName ];
		}

		if (matches.size() == 0) {
			return err(404, 'No contact matching: ' + reqName);
		} else if (matches.size() > 1) {
			return err(400, 'Multiple contact matches to: ' + reqName);
		}

		Contact c = matches[0];
		Map<String, Object> reqMap;
		try {
			reqMap = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString()); // UTF-8 encoding
		} catch(Exception parseErr) {
			return err(400, 'Expected JSON Object request payload');
		}

		return JSON.serialize(new Map<String, Object>{ 'status' => 'success', 'salesforceId' => c.Id });
	}

	static String err(Integer statusCode, String msg) {
		RestContext.response.statusCode = statusCode;
		return JSON.serialize(new Map<String, Object>{ 'status' => 'error', 'message' => msg });
	}
}