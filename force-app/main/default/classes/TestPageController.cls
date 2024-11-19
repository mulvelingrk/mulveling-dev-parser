public class TestPageController {

    public String emptyStr {get; private set;}
    public String blankStr {get; private set;}
    public String nullStr {get; private set;}
    public String fooStr {get; private set;}
    
    public String someId {get; private set;}

    
    public TestPageController () {
        emptyStr = '';
        blankStr = '      ';
        nullStr = null;
        fooStr = 'foo';
        someId = '"abc"&>';
    }
}