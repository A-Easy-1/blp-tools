#import "LocalHttpServer.h"
#import <CFNetwork/CFNetwork.h>
#import <UIKit/UIKit.h>
#import <ifaddrs.h>
#import <arpa/inet.h>

@interface LocalHttpServer ()
@property (nonatomic, strong) NSThread *serverThread;
@property (nonatomic, assign) CFSocketRef socket;
@end

@implementation LocalHttpServer

+ (instancetype)shared {
    static LocalHttpServer *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)startServer {
    self.serverThread = [[NSThread alloc] initWithTarget:self selector:@selector(runServer) object:nil];
    [self.serverThread start];
}

- (void)runServer {
    @autoreleasepool {
        int port = 8080;  // Change this if needed

        CFSocketContext socketContext = {0, (__bridge void *)(self), NULL, NULL, NULL};
        self.socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP,
                                     kCFSocketAcceptCallBack, ServerAcceptCallback, &socketContext);
        
        if (!self.socket) {
            NSLog(@"Failed to create socket");
            return;
        }

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_len = sizeof(addr);
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_ANY);
        addr.sin_port = htons(port);

        CFDataRef address = CFDataCreate(NULL, (const UInt8 *)&addr, sizeof(addr));
        CFSocketSetAddress(self.socket, address);
        CFRelease(address);

        NSLog(@"Local HTTP Server started at: http://%@:%d", [self getIPAddress], port);

        CFRunLoopSourceRef runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, self.socket, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);

        CFRunLoopRun();
    }
}

// Accept new connection
static void ServerAcceptCallback(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    if (type != kCFSocketAcceptCallBack) return;

    LocalHttpServer *server = (__bridge LocalHttpServer *)info;
    int clientSocket = *(int *)data;
    [server handleRequest:clientSocket];
}

- (void)handleRequest:(int)clientSocket {
    char buffer[1024];
    read(clientSocket, buffer, sizeof(buffer) - 1);
    
    NSString *request = [NSString stringWithUTF8String:buffer];
    NSString *requestedFile = [[request componentsSeparatedByString:@" "] objectAtIndex:1];

    // If root URL ("/") is requested, return a file listing
    if ([requestedFile isEqualToString:@"/"]) {
        [self sendDirectoryListing:clientSocket];
    } else {
        [self serveFile:clientSocket withPath:requestedFile];
    }
    
    close(clientSocket);
}

// Get the local IP address
- (NSString *)getIPAddress {
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    NSString *address = nil;

    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *ifaName = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([ifaName isEqualToString:@"en0"]) { // Wi-Fi interface
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address ? address : @"127.0.0.1";
}


// Serve a file from the Documents directory
- (void)serveFile:(int)clientSocket withPath:(NSString *)requestedFile {
    NSString *filePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
                          stringByAppendingPathComponent:[requestedFile lastPathComponent]];

    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSData *fileData = [NSData dataWithContentsOfFile:filePath];
        NSString *header = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Length: %lu\r\n\r\n", (unsigned long)fileData.length];
        write(clientSocket, header.UTF8String, strlen(header.UTF8String));
        write(clientSocket, fileData.bytes, fileData.length);
    } else {
        NSString *notFoundResponse = @"HTTP/1.1 404 Not Found\r\n\r\nFile Not Found";
        write(clientSocket, notFoundResponse.UTF8String, strlen(notFoundResponse.UTF8String));
    }
}

// Generate a simple HTML file listing
- (void)sendDirectoryListing:(int)clientSocket {
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentsPath error:nil];

    NSMutableString *html = [NSMutableString stringWithString:@"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n"];
    [html appendString:@"<html><head><title>File List</title></head><body>"];
    [html appendString:@"<h1>Available Files</h1><ul>"];

    for (NSString *file in files) {
        NSString *fileURL = [NSString stringWithFormat:@"<li><a href=\"/%@\">%@</a></li>", file, file];
        [html appendString:fileURL];
    }

    [html appendString:@"</ul></body></html>"];

    write(clientSocket, html.UTF8String, strlen(html.UTF8String));
}


@end
