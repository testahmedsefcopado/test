public class Greeting {
    public String name;

    // Constructor
    public Greeting(String name) {
        this.name = name;
    }

    public String sayHello() {
        return 'Hello, ' + name + '!';
    }
}