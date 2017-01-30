public with sharing class CustomArticleManagementController {
	public static Map<Id, SObject> allArticleTypeDataMap = new Map<Id, SObject>();
	public static Map<String, String> languageCodeToLanguage = new Map<String, String>();
	public static Map<String, String> languageToLanguageCode = new Map<String, String>();
	
	/*
	** Each time a new article type is created the <article-type>__kav must be injected into the allArticleTypeDataMap
	** Currently supporting for only Published/Online articles to be cloned
	*/
	static {
		Schema.DescribeFieldResult fieldResult = User.LanguageLocaleKey.getDescribe();
		List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
		for (Schema.PicklistEntry picklistEntry : picklistValues) {
			//language
			String language = picklistEntry.getLabel();
			//languageCode
			String languageCode = picklistEntry.getValue();

			languageCodeToLanguage.put(languageCode, language);
			languageToLanguageCode.put(language, languageCode);
		}

		//System.debug('static');
		// get data from Knowledge_kav
		for(Knowledge__kav elem : [SELECT Id,Title,UrlName,Summary, Body__c, ArticleType, KnowledgeArticleId FROM Knowledge__kav WHERE PublishStatus = 'Online' AND Language = 'en_US']) {
			//System.debug(elem);
			allArticleTypeDataMap.put(elem.Id, elem);
			//System.debug(allArticleTypeDataMap);
		}

		// get data from Programming_Language__kav
		for(Programming_Language__kav elem : [SELECT Id,Title,UrlName,Summary, Body__c, Rich_Body__c, ArticleType, KnowledgeArticleId FROM Programming_Language__kav WHERE PublishStatus = 'Online' AND Language = 'en_US']) {
			//System.debug(elem);
			allArticleTypeDataMap.put(elem.Id, elem);
			//System.debug(allArticleTypeDataMap);
		}
	}

	/*
	** Each Knowlege article is mapped to KnowledgeArticleVersion with gives the necessary fields like ArticleType, Title, etc.
	** Currently supporting for only Published/Online articles to be cloned
	*/
	@RemoteAction
	public static List<KnowledgeArticleVersion> retreiveKnowledgeArticleVersionList(String lang) {
		String l = 'en_US';
		String status = 'Online';
		return Database.query('SELECT Id, KnowledgeArticleId, ArticleType, Title, Summary, Language FROM KnowledgeArticleVersion WHERE PublishStatus = :status AND Language = :lang');
	}

	/*
	** Get supported languages
	*/
	@RemoteAction
	public static AvailableLanguagesCls retrieveSupportedLanguages() {
		AvailableLanguagesCls languages;

		String response = '';

		Http h = new Http();
		HttpRequest req = new HttpRequest();

		String endpoint_x = URL.getSalesforceBaseUrl().toExternalForm() + '/services/data/v37.0/knowledgeManagement/settings';

		req.setEndpoint(endpoint_x);
		req.setMethod('GET');
		req.setHeader('Authorization', 'Bearer '+UserInfo.getSessionId());
		req.setHeader('Content-Type', 'application/json; charset=UTF-8');
		req.setHeader('Accept', 'application/json');

		try {
			HttpResponse res = h.send(req);
			if(res.getStatusCode() == 200) {
				response = res.getBody();
				System.debug(response);
				languages = (AvailableLanguagesCls)JSON.deserialize(response, AvailableLanguagesCls.class);
				System.debug(languages);
				languages.status = 'SUCCESS';
				languages.langCodeToLanguage = languageCodeToLanguage;
				return languages;
			}else if(res.getStatusCode() == 401) {
				languages = new AvailableLanguagesCls();
				languages.status = 'ERROR:'+res.getStatus()+' @method: retrieveSupportedLanguages';
				return languages;
			}else {
				languages = new AvailableLanguagesCls();
				languages.status = 'ERROR:'+res.getStatus()+'::'+res.getStatusCode()+' @method: retrieveSupportedLanguages';
				return languages;
			}
		}catch(Exception e) {
			System.debug(e.getStackTraceString());
			languages = new AvailableLanguagesCls();
			languages.status = 'ERROR:Can\'t retrieve the languages;'+e.getStackTraceString()+' @method: retrieveSupportedLanguages';
		}

		return null;
	}

	class AvailableLanguagesCls {
		String defaultLanguage;
		Boolean knowledgeEnabled;
		List<LanguageCls> languages;
		String status;
		Map<String, String> langCodeToLanguage;

		AvailableLanguagesCls() {}

		AvailableLanguagesCls(String defaultLanguage, Boolean knowledgeEnabled, List<LanguageCls> languages) {
			this.defaultLanguage = defaultLanguage;
			this.knowledgeEnabled = knowledgeEnabled;
			this.languages = languages;
		}
	} 

	class LanguageCls {
		Boolean active;
		String name;

		LanguageCls(Boolean active, String name){
			this.active = active;
			this.name = name;
		}
	}

	/*
	** In order to clone a Knowledge article first it has to be submitted for translation. Using PublishingService under KbManagement 
	** namespace a published article can be submitted for translation. In order to submit a knowledge article for translation, it requires 
	** KnowledgeArticleID, which is a custom field of KnolwedgeArticleVersion and secondly it needs the language of the target translation.
	** Once translation is done, the custom fields data of the original article is retrieved using articleType as object and Id field of 
	** KnowledgeArticleVersion. The PublishingService gives a newly created object of articletype and it's Id is articleVersionId. Using 
	** dynamic dml it's body can be set using the body abtained in above step.
	*/
	@RemoteAction
	public static String cloneKnowledgeArticleData(String selectedArticles) {
		System.debug(selectedArticles);
		List<SObject> clones = new List<SObject>();
			
		for(ArticleCls item : (List<ArticleCls>)JSON.deserialize(selectedArticles, List<ArticleCls>.class)) {
			System.debug(item);

			String assigneeId = UserInfo.getUserId();
			Datetime dueDate = Datetime.newInstanceGmt(2017, 1,28);
			String lang = 'fr';

			String articleId = '';
			try {
				articleId = KbManagement.PublishingService.submitForTranslation(item.kaId, lang, assigneeId, dueDate);
				System.debug('articleId '+articleId);
			} catch(Exception e) {
				System.debug(e);
				return e.getMessage();
			}
	        
	    	System.debug(allArticleTypeDataMap);
			
			if(allArticleTypeDataMap.get(item.kavId) == null) {
				KbManagement.PublishingService.deleteDraftTranslation (articleId);
			} else {
				System.debug(allArticleTypeDataMap.get(item.kavId));	
				SObject data = allArticleTypeDataMap.get(item.kavId);

				// Each time a new article type is created the <article-type>__kav must be injected into the the conditionals below
				if(item.aType == 'Knowledge__kav') {
					Knowledge__kav temp = (Knowledge__kav) data;
					temp.Id = articleId;
					clones.add(temp);
				} else if(item.aType == 'Programming_Language__kav') {
					Programming_Language__kav temp = (Programming_Language__kav) data;
					temp.Id = articleId;
					clones.add(temp);
				}
			}
		}

		try {
			// log successfull clones, delete the rest of them
			Database.SaveResult[] srList = Database.update(clones, false);
			for(Database.SaveResult sr : srList) {
			    if (sr.isSuccess()) {
			        // Operation was successful, so get the ID of the record that was processed
			        System.debug('Successfully cloned article ID: ' + sr.getId());
			    } else {
			        // Operation failed, so get all errors                
			        for(Database.Error err : sr.getErrors()) {
		        		// delete failed clones
		        		KbManagement.PublishingService.deleteDraftTranslation(sr.getId());
			            System.debug('The following error has occurred.');                    
			            System.debug(err.getStatusCode() + ': ' + err.getMessage());
			            System.debug('Cloned article fields that affected this error: ' + err.getFields());
				    }
		    	}
			}
		} catch(Exception e) {
			System.debug(e);
			return e.getMessage();
		}

		return 'SUCCESS';
	}

	class ArticleCls {
		String kavId;
		String kaId;
		String aType;

		ArticleCls(String kavId, String kaId, String aType) {
			this.kavId = kavId;
			this.kaId = kaId;
			this.aType = aType;
		}
	}
}