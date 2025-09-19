public with sharing class SimpleEPAEx {
    
    // Public variable
    public String message { get; set; }

    // Constructor
    public SimpleEPAEx() {
        this.message = 'Hello from SimpleEPAEx!';
    }

    // Method to return the message
    public String getMessage() {
        return message;
    }

    // Static method to return a greeting
    public static String staticGreeting() {
        return 'Hello from Static Method!';
    }
}