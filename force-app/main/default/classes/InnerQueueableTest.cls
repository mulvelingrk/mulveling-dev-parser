public class InnerQueueableTest {
    public class InnerQ implements System.Queueable {
        public String name;
        
        InnerQ(String name) {
            this.name = name;
        }
        
        public void execute(System.QueueableContext qc) {
            System.debug('Hello World! My name is ' + name);
        }
    }
    
    public static Id kickoff() {
        return System.enqueueJob(new InnerQ('Fred'));
    }
}