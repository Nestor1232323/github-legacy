#import <UIKit/UIKit.h>

@interface ViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIWebViewDelegate, UIScrollViewDelegate>

@property (weak, nonatomic) IBOutlet UITableView *tableView;

@property (weak, nonatomic) IBOutlet UITableView *profiletableView;
@property (nonatomic, strong) NSDictionary *userInfo;

@property (strong, nonatomic) NSString *userName;
@property (strong, nonatomic) NSString *avatarURL;
@property (nonatomic, strong) NSString *username;
@property (nonatomic, strong) NSArray *fileList;

- (NSString *)formatFileSize:(NSNumber *)sizeInBytes;
@property (nonatomic, strong) NSArray *repositories;
@property (nonatomic, strong) NSArray *repoFiles;
@property (nonatomic, strong) NSArray *dataArray;
@property (nonatomic, assign) BOOL showingRepositories;
@property (nonatomic, strong) NSDictionary *selectedRepo;

@property (nonatomic, strong) NSMutableData *receivedData;
@property (nonatomic, strong) UIImage *userAvatar;
@property (nonatomic, strong) NSDictionary *selectedReleaseForDownload;


@property (nonatomic, strong) NSDictionary *selectedFile;
@property (nonatomic, strong) NSURLConnection *fileConnection;
@property (nonatomic, assign) long long totalFileSize;
@property (nonatomic, strong) NSString *downloadFileName;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) NSArray *repoReleases;
@property (nonatomic, assign) BOOL showingReleases;
@property (nonatomic, strong) NSString *selectedReleaseURL;

@property (nonatomic, strong) NSIndexPath *downloadingIndexPath;

@property (nonatomic, strong) NSString *pendingDownloadURL;
@property (nonatomic, strong) NSString *pendingDownloadFileName;

@end
