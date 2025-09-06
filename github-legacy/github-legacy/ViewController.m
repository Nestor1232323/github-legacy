#import "ViewController.h"
#import <MediaPlayer/MediaPlayer.h>

@interface ViewController ()
@property (nonatomic, strong) NSString *currentPath;
@property (nonatomic, strong) NSString *currentRepoName;
@property (nonatomic, strong) NSString *pendingFolderName;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    self.repositories = @[];
    self.repoFiles = @[];
    
    self.showingRepositories = YES;
    // не не не добавляеться
    UIBarButtonItem *clearButton = [[UIBarButtonItem alloc] initWithTitle:@"Очистить"
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(clearMemoryCache)];
    
    [self setupProfileTableView];
    self.navigationItem.rightBarButtonItem = clearButton;
    
    NSString *savedUsername = [self loadSavedUsername];
    if (savedUsername && savedUsername.length > 0) {
        self.username = savedUsername;
        [self fetchUserData];
        [self fetchRepositories];
    } else {
        [self showPopupWithTextField];
    }
    
    UILongPressGestureRecognizer *longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.tableView addGestureRecognizer:longPressRecognizer];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    
    [self.tableView addSubview:self.refreshControl];
}

// чтобы телефон не взорвался
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    
    if (self.showingRepositories == NO) {
        self.userAvatar = nil;
    }
    
    NSLog(@"Memory warning received - cleared caches");
}

// метод для ленивых - грузим только когда нужно
- (void)fetchFiles {
    if (self.currentRepoName && self.currentPath != nil) {
        [self fetchRepositoryContents:self.currentRepoName atPath:self.currentPath];
    } else {
        // а что ты вообще хотел, если ничего не выбрано?
        NSLog(@"Нечего грузить, иди отсюда");
    }
}

// загрузки, обновления... хотя кому нахер оно нужно?
- (void)handleRefresh:(UIRefreshControl *)refreshControl {
    if (self.showingRepositories) {
        [self fetchRepositories];
    } else if (self.showingReleases) {
        [self fetchReleases:self.currentRepoName]; // парсим
    } else {
        [self fetchFiles];
    }
}
#pragma mark - Memory Management

// метод для тех, кто верит в чудеса
- (void)clearMemoryCache {
    self.repoFiles = nil; // чистим файлы (они все равно никому не нужны)
    self.repositories = nil; // чистим репозитории (загрузим заново)
    self.userAvatar = nil; // чистим аватар (пользователь и так его видел)
    
    // делаем вид, что чистим кэш
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    
    // перезагружаем данные, чтобы пользователь подумал, что что-то произошло
    [self fetchUserData];
    [self fetchRepositories];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        CGPoint touchPoint = [sender locationInView:self.tableView];
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:touchPoint];
        
        if (indexPath) {
            if (self.showingRepositories) {
                // ну... мы в списке репо
                if (indexPath.row > 0) {
                    // словари.
                    NSDictionary *repo = self.repositories[indexPath.row - 1];
                    [self showRepoActionSheet:repo];
                }
            } else {
                // пока пока кнопка назад :(
                if (indexPath.row > 0) {
                    NSDictionary *file = self.repoFiles[indexPath.row - 1];
                    NSString *type = file[@"type"];
                    if ([type isEqualToString:@"file"]) {
                        [self showFileActionSheet:file];
                    }
                }
            }
        }
    }
}

- (void)showRepoActionSheet:(NSDictionary *)repo {
// на всякий, сохраняем инфу, но как смеенить её? в следующих версиях... если не забуду
    self.selectedRepo = repo;
    
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:repo[@"name"]
                                                             delegate:self // почему ошибка??
                                                    cancelButtonTitle:@"Отмена"
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:@"Скопировать URL", @"Просмотреть в Safari", @"Показать релизы", nil];
    
    actionSheet.tag = 2002;
    [actionSheet showInView:self.view];
}


- (void)showFileActionSheet:(NSDictionary *)file {
    // информация, о файле...
    self.selectedFile = file;
    
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:file[@"name"]
                                                             delegate:self // мне лень её чинить.
                                                    cancelButtonTitle:@"Отмена"
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:@"Открыть", @"Скачать", nil];
    
    actionSheet.tag = 2001; // необычный годик конечно
    
    [actionSheet showInView:self.view];
}

// обработка кнопочек
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag == 2001) {
        // ну... надеюсь разберусь (нет)
        if (buttonIndex == 0) {
            [self openFile:self.selectedFile];
        } else if (buttonIndex == 1) {
            [self downloadFile:self.selectedFile];
        }
    } else if (actionSheet.tag == 2002) {
        if (buttonIndex == 0) {
            NSString *repoURL = self.selectedRepo[@"html_url"];
            if (repoURL) {
                UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                pasteboard.string = repoURL;
                
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Готово!"
                                                                message:@"URL репозитория скопирован в буфер обмена"
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
                [alert show];
            }
        } else if (buttonIndex == 1) {
            NSString *repoURL = self.selectedRepo[@"html_url"];
            if (repoURL) {
                NSURL *url = [NSURL URLWithString:repoURL];
                [[UIApplication sharedApplication] openURL:url];
            }
        } else if (buttonIndex == 2) {
            // о привет релиз!!!!!
            [self fetchReleases:self.selectedRepo[@"name"]];
        }
    }
}
// получаем релизы
- (void)fetchReleases:(NSString *)repoName {
    NSString *usernameToFetch = self.username ? self.username : @"Nestor1232323";
    NSString *urlString = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/releases", usernameToFetch, repoName];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               if (self.refreshControl.isRefreshing) {
                                   [self.refreshControl endRefreshing];
                               }
                               
                               if (!error) {
                                   NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                                   if (httpResponse.statusCode != 200) {
                                       NSLog(@"HTTP Error: %ld", (long)httpResponse.statusCode);
                                       self.repoReleases = @[];
                                       self.showingReleases = YES;
                                       [self.tableView reloadData];
                                       return;
                                   }
                                   
                                   id jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                                   
                                   if (jsonResponse && [jsonResponse isKindOfClass:[NSArray class]]) {
                                       self.repoReleases = (NSArray *)jsonResponse;
                                       self.showingReleases = YES;
                                       self.showingRepositories = NO;
                                       [self.tableView reloadData];
                                   } else {
                                       NSLog(@"GitHub API returned non-array response for releases: %@", jsonResponse);
                                       self.repoReleases = @[];
                                       self.showingReleases = YES;
                                       self.showingRepositories = NO;
                                       [self.tableView reloadData];
                                   }
                               } else {
                                   NSLog(@"Error fetching releases: %@", error.localizedDescription);
                                   self.repoReleases = @[];
                                   self.showingReleases = YES;
                                   self.showingRepositories = NO;
                                   [self.tableView reloadData];
                               }
                           }];
}

// метод для тех, кто любит ждать
- (void)downloadFile:(NSDictionary *)file {
    NSString *downloadURL = file[@"download_url"];
    NSString *fileName = file[@"name"];
    
    if (!downloadURL || !fileName) {
        // классика - "ошибка", но какая - хз
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Ошибка"
                                                        message:@"Не удалось получить URL для скачивания"
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }
    
    // покажем пользователю, что что-то происходит, а то заскучает
    UIAlertView *startAlert = [[UIAlertView alloc] initWithTitle:@"Загрузка..."
                                                         message:[NSString stringWithFormat:@"Начинается загрузка файла %@", fileName]
                                                        delegate:nil
                                               cancelButtonTitle:nil
                                               otherButtonTitles:nil];
    [startAlert show];
    
    // делаем вид, что работаем в фоне
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        // реальная работа (нет)
        NSData *fileData = [NSData dataWithContentsOfURL:[NSURL URLWithString:downloadURL]];
        
        // возвращаемся в главный поток, чтобы пользователь не подумал, что все сломалось
        dispatch_async(dispatch_get_main_queue(), ^{
            [startAlert dismissWithClickedButtonIndex:0 animated:YES]; // закрываем уведомление
            
            if (fileData) {
                // сохраняем файл куда-то в документы, где он все равно никому не нужен
                NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                NSString *filePath = [documentsPath stringByAppendingPathComponent:fileName];
                
                BOOL success = [fileData writeToFile:filePath atomically:YES];
                
                if (success) {
                    // ура, файл сохранен! (хотя кому это нужно)
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Успешно!"
                                                                    message:[NSString stringWithFormat:@"Файл %@ сохранен в папку Documents\nРазмер: %.1f КБ", fileName, (float)fileData.length / 1024.0]
                                                                   delegate:nil
                                                          cancelButtonTitle:@"OK"
                                                          otherButtonTitles:nil];
                    [alert show];
                } else {
                    // ну хоть попытались...
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Ошибка"
                                                                    message:[NSString stringWithFormat:@"Не удалось сохранить файл %@", fileName]
                                                                   delegate:nil
                                                          cancelButtonTitle:@"OK"
                                                          otherButtonTitles:nil];
                    [alert show];
                }
            } else {
                // интернета нет, но вы держитесь
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Ошибка"
                                                                message:[NSString stringWithFormat:@"Не удалось загрузить файл %@", fileName]
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
                [alert show];
            }
        });
    });
}

#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    self.totalFileSize = [response expectedContentLength];
    [self.receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.receivedData appendData:data];
    
    // ui-шки хехе
    if (self.totalFileSize > 0 && self.downloadingIndexPath) {
        float progress = (float)self.receivedData.length / self.totalFileSize;
        
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:self.downloadingIndexPath];
        if (cell) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f%% загружено", progress * 100]; // надеюсь это не заглушка :p
        }
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    // у нас есть файлы!!!
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *filePath = [documentsPath stringByAppendingPathComponent:self.downloadFileName];
    
    BOOL success = [self.receivedData writeToFile:filePath atomically:YES];
    
    UITableViewCell *cell = nil;
    if (self.downloadingIndexPath) {
        cell = [self.tableView cellForRowAtIndexPath:self.downloadingIndexPath];
    }
    
    if (success) {
        if (cell) {
            cell.accessoryView = nil;
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            
            // а зачем получать файлы с диска? на всякий...
            NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            NSNumber *fileSize = fileAttributes[NSFileSize];
            if (fileSize) {
                cell.detailTextLabel.text = [self formatFileSize:fileSize];
            } else {
                cell.detailTextLabel.text = @"Размер неизвестен";
            }
        }
    } else {
        if (cell) {
            cell.accessoryView = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.detailTextLabel.text = @"Ошибка сохранения";
        }
    }
    
    self.receivedData = nil;
    self.fileConnection = nil;
    self.downloadingIndexPath = nil;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:self.downloadingIndexPath];
    UIView *activityIndicator = [cell viewWithTag:100];
    if (activityIndicator) {
        [activityIndicator removeFromSuperview];
    }
    
    if (cell) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Ошибка: %@", [error localizedDescription]];
    }
    // интернета нет но вы держитесь :p
    
    self.receivedData = nil;
    self.fileConnection = nil;
    self.downloadingIndexPath = nil;
}

- (NSString *)documentsDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths objectAtIndex:0];
}

#pragma mark - GitHub API
// userdata...
- (void)fetchUserData {
    NSString *usernameToFetch = self.username ? self.username : @"Nestor1232323";
    NSString *urlString = [NSString stringWithFormat:@"https://api.github.com/users/%@", usernameToFetch];
    NSURL *url = [NSURL URLWithString:urlString];  
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"GitHubLegacy" forHTTPHeaderField:@"User-Agent"];
                    // ^^^ чтобы ошибки 403 было редко :p
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               if (!error) {
                                   NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                                   if (jsonResponse) {
                                       self.userInfo = jsonResponse;
                                       
                                       self.userName = jsonResponse[@"name"] != [NSNull null] ? jsonResponse[@"name"] : @"Неизвестно";
                                       
                                       NSString *avatarURLString = jsonResponse[@"avatar_url"];
                                       if (avatarURLString && avatarURLString != (id)[NSNull null]) {
                                           NSURL *avatarURL = [NSURL URLWithString:avatarURLString];
                                           dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                                               NSData *imageData = [NSData dataWithContentsOfURL:avatarURL];
                                               if (imageData) {
                                                   UIImage *avatar = [UIImage imageWithData:imageData];
                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                       self.userAvatar = avatar;
                                                       [self.profiletableView reloadData];
                                                   });
                                               }
                                           });
                                       } else {
                                           [self.profiletableView reloadData];
                                       }
                                   }
                               } else {
                                   NSLog(@"Error fetching user data: %@", error.localizedDescription);
                               } // мб инета нет
                           }];
}
// чтобы смотреть репо линуса торвальдса
- (void)fetchRepositories {
    if (self.refreshControl.isRefreshing) {
        [self.refreshControl endRefreshing];
    }
    NSString *usernameToFetch = self.username ? self.username : @"Nestor1232323";
    NSString *urlString = [NSString stringWithFormat:@"https://api.github.com/users/%@/repos", usernameToFetch];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               if (!error) {
                                   NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                                   if (httpResponse.statusCode != 200) {
                                       NSLog(@"HTTP Error: %ld", (long)httpResponse.statusCode);
                                       self.repositories = @[];
                                       [self.tableView reloadData];
                                       return;
                                   }
                                   
                                   id jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                                   
                                   if (jsonResponse && [jsonResponse isKindOfClass:[NSArray class]]) {
                                       self.repositories = (NSArray *)jsonResponse;
                                       self.showingRepositories = YES;
                                       [self.tableView reloadData];
                                   } else {
                                       NSLog(@"GitHub API returned non-array response: %@", jsonResponse);
                                       self.repositories = @[];
                                       self.showingRepositories = YES;
                                       [self.tableView reloadData];
                                   }
                               } else {
                                   NSLog(@"Error fetching repositories: %@", error.localizedDescription);
                                   self.repositories = @[];
                                   [self.tableView reloadData];
                               }
                           }];
}

// ааа... контент ура, наконец я добавил спустя 7-8 месяцов
- (void)fetchRepositoryContents:(NSString *)repoName atPath:(NSString *)path {
    if (self.refreshControl.isRefreshing) {
        [self.refreshControl endRefreshing];
    }
    NSString *usernameToFetch = self.username ? self.username : @"Nestor1232323";
    NSString *urlString;
    
    if (path && path.length > 0) {
        urlString = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/contents/%@", usernameToFetch, repoName, path];
    } else {
        urlString = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/contents", usernameToFetch, repoName];
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               if (!error) {
                                   NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                                   if (httpResponse.statusCode != 200) {
                                       NSLog(@"HTTP Error: %ld", (long)httpResponse.statusCode);
                                       self.repoFiles = @[];
                                       [self.tableView reloadData];
                                       return;
                                   }
                                   
                                   id jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                                   
                                   if (jsonResponse && [jsonResponse isKindOfClass:[NSArray class]]) {
                                       NSArray *fullArray = (NSArray *)jsonResponse;
                                       
                                       
                                       NSArray *limitedArray;
                                       if (fullArray.count > 100) {
                                           NSLog(@"Warning: Folder has %lu items, showing only first 100", (unsigned long)fullArray.count);
                                           limitedArray = [fullArray subarrayWithRange:NSMakeRange(0, 100)];
                                       } else {
                                           limitedArray = fullArray;
                                       }
                                       
                                       self.repoFiles = nil;
                                       
                                       self.repoFiles = limitedArray;
                                       self.showingRepositories = NO;
                                       [self.tableView reloadData];
                                       
                                   } else {
                                       NSLog(@"GitHub API returned non-array response for contents: %@", jsonResponse);
                                       self.repoFiles = @[];
                                       self.showingRepositories = NO;
                                       [self.tableView reloadData];
                                   }
                               } else {
                                   NSLog(@"Error fetching repository contents: %@", error.localizedDescription);
                                   self.repoFiles = @[];
                                   [self.tableView reloadData];
                               }
                           }];
}
// представьте, что оно что-то делает
#pragma mark - UITableView DataSource / Delegate
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.profiletableView) {
        return [self profileTableViewNumberOfRowsInSection:section];
    }
    
    if (tableView.tag == 7777) {
        NSArray *assets = self.selectedReleaseForDownload[@"assets"];
        return assets ? assets.count : 0;
    }
    
    if (self.showingRepositories) {
        if (self.repositories.count == 0) {
            return 2;
        }
        return self.repositories.count + 1;
    } else if (self.showingReleases) {
        if (self.repoReleases.count == 0) {
            return 2;
        }
        return self.repoReleases.count + 1;
    } else {
        if (self.repoFiles.count == 0) {
            return 2;
        }
        return self.repoFiles.count + 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (tableView == self.profiletableView) {
        return [self profileTableViewTitleForHeaderInSection:section];
    }
    return nil;
}
// оо да, обработка файлов :p
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    
    if (tableView == self.profiletableView) {
        return [self profileTableViewCellForRowAtIndexPath:indexPath];
    }
    
    if (tableView.tag == 7777) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        }
        
        NSArray *assets = self.selectedReleaseForDownload[@"assets"];
        if (indexPath.row < assets.count) {
            NSDictionary *asset = assets[indexPath.row];
            
            cell.textLabel.text = asset[@"name"] ?: @"Неизвестный файл"; // ошибка, не скажу какая сами разберайтесь
            
            NSNumber *size = asset[@"size"];
            NSString *sizeString = [self formatFileSize:size];
            cell.detailTextLabel.text = sizeString;
            
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            cell.detailTextLabel.textColor = [UIColor grayColor];
            
            cell.textLabel.textColor = [UIColor blackColor];
            cell.imageView.image = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
            
            if ([self.downloadingIndexPath isEqual:indexPath]) {
                UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                [activityIndicator startAnimating];
                activityIndicator.tag = 100;
                cell.accessoryView = activityIndicator;
            } else {
                cell.accessoryView = nil;
            }
            
        }
        
        return cell;
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.detailTextLabel.textColor = [UIColor grayColor];
    
    cell.textLabel.textColor = [UIColor blackColor];
    cell.imageView.image = nil;
    if (self.showingRepositories) {
        if (indexPath.row == 0) {
            cell.textLabel.text = self.userName ?: @"Неизвестно";
            cell.imageView.image = self.userAvatar ?: [UIImage imageNamed:@"placeholder"]; // placeholder'ы...
        } else if (self.repositories.count == 0 && indexPath.row == 1) {
            cell.textLabel.text = @"Тут пусто..."; // юзер не создал папки внутри репо :p
            cell.textLabel.textColor = [UIColor grayColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            NSInteger repoIndex = indexPath.row - 1;
            if (self.repositories && repoIndex >= 0 && repoIndex < self.repositories.count) {
                NSDictionary *repo = self.repositories[repoIndex];
                cell.textLabel.text = repo[@"name"] ?: @"Неизвестный репозиторий"; // 403 ошибка??
            } else {
                cell.textLabel.text = @"Ошибка загрузки"; // наверняка :p
            }
        }
        
    } else if (self.showingReleases) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"⬅︎ Назад к репозиториям"; // оо моя любимая кнопка назад, как же тебя не хватало
        } else if (self.repoReleases.count == 0 && indexPath.row == 1) {
            cell.textLabel.text = @"Тут пусто...";
            cell.textLabel.textColor = [UIColor grayColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            NSInteger releaseIndex = indexPath.row - 1;
            if (self.repoReleases && releaseIndex >= 0 && releaseIndex < self.repoReleases.count) {
                NSDictionary *release = self.repoReleases[releaseIndex];
                cell.textLabel.text = release[@"name"] ?: release[@"tag_name"] ?: @"Неизвестный релиз";
                
                cell.detailTextLabel.text = @"";
            } else {
                cell.textLabel.text = @"Ошибка загрузки";
            }
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"⬅︎ Назад"; // и снова привет!! !
            cell.imageView.image = nil;
        } else if (self.repoFiles.count == 0 && indexPath.row == 1) {
            cell.textLabel.text = @"Тут пусто..."; // надеюсь это чел не заполнил репо :p
            cell.textLabel.textColor = [UIColor grayColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            NSInteger fileIndex = indexPath.row - 1;
            if (self.repoFiles && fileIndex >= 0 && fileIndex < self.repoFiles.count) {
                NSDictionary *file = self.repoFiles[fileIndex];
                NSString *fileType = file[@"type"];
                NSString *fileName = file[@"name"];
                
                cell.textLabel.text = fileName ?: @"Неизвестный файл";
                
                if ([fileType isEqualToString:@"dir"]) {
                    cell.detailTextLabel.text = @"Папка"; // надо было написать директория, ну ладно я же не linux юзер
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                } else {
                    cell.imageView.image = [UIImage imageNamed:@"file"]; // файлы
                    cell.accessoryType = UITableViewCellAccessoryNone;
                    
                    if ([self.downloadingIndexPath isEqual:indexPath]) {
                        UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                        [activityIndicator startAnimating];
                        activityIndicator.tag = 100;
                        cell.accessoryView = activityIndicator;
                    } else {
                        cell.accessoryView = nil;
                    }
                    
                    NSNumber *size = file[@"size"]; // чтобы не скачать 1 гб файл на телефон
                    cell.detailTextLabel.text = [self formatFileSize:size];
                }
            } else {
                cell.textLabel.text = @"Ошибка загрузки";
            }
        }
    }
    return cell;
}

- (void)downloadReleaseAsset:(NSDictionary *)asset {
    NSString *downloadURL = asset[@"browser_download_url"];
    NSString *fileName = asset[@"name"];
    NSNumber *fileSize = asset[@"size"];
    
    if (!downloadURL || !fileName) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Ошибка"
                                                        message:@"Не удалось получить URL для скачивания" // не скажем почему :p
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }
    
    NSString *sizeString = [self formatFileSize:fileSize];
    NSString *message = [NSString stringWithFormat:@"Скачать файл '%@'?\nРазмер: %@", fileName, sizeString];
    
    UIAlertView *confirmAlert = [[UIAlertView alloc] initWithTitle:@"Скачивание" // не, эт не работает
                                                           message:message
                                                          delegate:self
                                                 cancelButtonTitle:@"Отмена"
                                                 otherButtonTitles:@"Скачать", nil];
    confirmAlert.tag = 4001;
    
    self.pendingDownloadURL = downloadURL;
    self.pendingDownloadFileName = fileName;
    
    [confirmAlert show];
}

- (void)handleDownloadConfirmation:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        [self startAssetDownload:self.pendingDownloadURL fileName:self.pendingDownloadFileName];
    }
    
    self.pendingDownloadURL = nil;
    self.pendingDownloadFileName = nil;
}
// релизы НЕ скачиваються, но бл*ть почему?
- (void)startAssetDownload:(NSString *)downloadURL fileName:(NSString *)fileName {
    UIAlertView *startAlert = [[UIAlertView alloc] initWithTitle:@"Загрузка..."
                                                         message:[NSString stringWithFormat:@"Начинается загрузка файла %@", fileName]
                                                        delegate:nil
                                               cancelButtonTitle:nil
                                               otherButtonTitles:nil];
    [startAlert show];
    
    NSURL *url = [NSURL URLWithString:downloadURL];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSData *fileData = [NSData dataWithContentsOfURL:url];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [startAlert dismissWithClickedButtonIndex:0 animated:YES];
            
            if (fileData) {
                NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                NSString *filePath = [documentsPath stringByAppendingPathComponent:fileName];
                
                BOOL success = [fileData writeToFile:filePath atomically:YES];
                
                if (success) {
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Успешно!"
                                                                    message:[NSString stringWithFormat:@"Файл релиза '%@' сохранен в папку Documents\nРазмер: %.1f КБ", fileName, (float)fileData.length / 1024.0]
                                                                   delegate:nil
                                                          cancelButtonTitle:@"OK" // это обман!!!!
                                                          otherButtonTitles:nil];
                    [alert show];
                } else {
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Ошибка"
                                                                    message:[NSString stringWithFormat:@"Не удалось сохранить файл '%@'", fileName]
                                                                   delegate:nil
                                                          cancelButtonTitle:@"OK"
                                                          otherButtonTitles:nil];
                    [alert show];
                }
            } else {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Ошибка"
                                                                message:[NSString stringWithFormat:@"Не удалось загрузить файл '%@'", fileName]
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
                [alert show];
            }
        });
    });
}

#pragma mark - UITableView Delegate

// проверочки например аватарки, хз
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (tableView == self.profiletableView) {
        return; // профиль тыкать бесполезно, но пусть будет
    }
    
    if (self.showingRepositories) {
        if (indexPath.row == 0) return; // это же аватарка, че ты тыкаешь?
        
        NSInteger repoIndex = indexPath.row - 1;
        if (self.repositories && repoIndex >= 0 && repoIndex < self.repositories.count) {
            NSDictionary *repo = self.repositories[repoIndex];
            self.currentRepoName = repo[@"name"];
            self.currentPath = @"";
            
            // о, это же священный репозиторий Линуса! будем осторожны
            if ([repo[@"name"] isEqualToString:@"linux"]) {
                [self showWarningForLargeRepo:repo[@"name"]];
            } else {
                // обычные репозитории можно грузить без предупреждений, кому они нужны
                [self fetchRepositoryContents:self.currentRepoName atPath:nil];
            }
        }
    } else if (self.showingReleases) {
        // назад - единственная полезная кнопка в этом view
        if (indexPath.row == 0) {
            self.showingReleases = NO;
            self.showingRepositories = YES;
            self.repoReleases = nil; // чистим мусор
            [self.tableView reloadData];
            return;
        }
        
        // пустые релизы - как пустая жизнь
        if (self.repoReleases.count == 0 && indexPath.row == 1) return;
        
        NSInteger releaseIndex = indexPath.row - 1;
        if (self.repoReleases && releaseIndex >= 0 && releaseIndex < self.repoReleases.count) {
            NSDictionary *release = self.repoReleases[releaseIndex];
            [self showReleaseDetails:release]; // покажем пользователю его бесполезные релизы
        }
    } else {
        // о, наконец-то кнопка назад! как же я по тебе соскучился...
        if (indexPath.row == 0) {
            [self backToPreviousPath];
        } else {
            NSInteger fileIndex = indexPath.row - 1;
            if (self.repoFiles && fileIndex >= 0 && fileIndex < self.repoFiles.count) {
                NSDictionary *file = self.repoFiles[fileIndex];
                NSString *type = file[@"type"];
                NSString *name = file[@"name"];
                
                if ([type isEqualToString:@"dir"]) {
                    // хз, тут проверка ТОЛЬКО на репо линуса... программе в падлу проверять другие репо...
                    if ([self.currentRepoName isEqualToString:@"linux"] &&
                        ([name isEqualToString:@"fs"] ||
                         [name isEqualToString:@"drivers"] ||
                         [name isEqualToString:@"include"])) {
                            self.pendingFolderName = name;
                            [self showWarningForLargeFolder:name]; // ой, тут много файлов, сейчас вылетим...
                        } else {
                            // обычные папки можно открывать без предупреждений
                            self.currentPath = [self.currentPath stringByAppendingPathComponent:name];
                            [self fetchRepositoryContents:self.currentRepoName atPath:self.currentPath];
                        }
                } else if ([type isEqualToString:@"file"]) {
                    [self openFile:file]; // попробуем открыть этот файл, если он не бинарник
                }
            }
        }
    }
}

- (void)showReleaseDetails:(NSDictionary *)release {
    NSString *title = release[@"name"] ?: release[@"tag_name"] ?: @"Безымянный релиз";
    NSString *body = release[@"body"] ?: @"Нет описания";
    NSString *publishedAt = [self formatGitHubDate:release[@"published_at"]];
    NSString *author = release[@"author"][@"login"] ?: @"Неизвестен";
    
// навсякий случай
    NSArray *assets = release[@"assets"];
    BOOL hasAssets = assets && [assets isKindOfClass:[NSArray class]] && assets.count > 0;
    
    NSString *message = [NSString stringWithFormat:@"Автор: %@\nДата: %@\n\n%@", author, publishedAt, body];
    
    UIAlertView *alert;
    if (hasAssets) {
        alert = [[UIAlertView alloc] initWithTitle:title
                                           message:message
                                          delegate:self
                                 cancelButtonTitle:@"Закрыть"
                                 otherButtonTitles:@"Открыть в Safari", @"Скачать файлы", nil];
        alert.tag = 3001; // тег для релизов с ассетами
    } else {
        alert = [[UIAlertView alloc] initWithTitle:title
                                           message:message
                                          delegate:self
                                 cancelButtonTitle:@"Закрыть"
                                 otherButtonTitles:@"Открыть в Safari", nil];
        alert.tag = 3002; // тег для релизов без ассетов
    }
    
    // сохраняем.
    self.selectedReleaseURL = release[@"html_url"];
    self.selectedReleaseForDownload = release;
    
    [alert show];
}

- (void)showReleaseAssetsForDownload:(NSDictionary *)release {
    NSArray *assets = release[@"assets"];
    if (!assets || ![assets isKindOfClass:[NSArray class]] || assets.count == 0) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Нет файлов"
                                                        message:@"У этого релиза нет файлов для скачивания"
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }
    
// ЭТО ЧТО ЗА ДИЧЬ??
    // ааа, спросил у ИИ это полноэкранный режим :p
    CGRect frame = self.view.bounds;
    UIView *containerView = [[UIView alloc] initWithFrame:frame];
    containerView.backgroundColor = [UIColor whiteColor];
    containerView.tag = 8888; // тег для контейнера ассетов
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, frame.size.width - 80, 30)];
    titleLabel.text = [NSString stringWithFormat:@"Файлы релиза: %@", release[@"tag_name"] ?: @""];
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [containerView addSubview:titleLabel];
    
    // тоже самое что и кнопка назад.
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(frame.size.width - 100, 40, 90, 30);
    [closeButton setTitle:@"Закрыть" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeAssetsView:) forControlEvents:UIControlEventTouchUpInside];
    [containerView addSubview:closeButton];
    
    UITableView *assetsTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 80, frame.size.width, frame.size.height - 80)];
    assetsTableView.delegate = self;
    assetsTableView.dataSource = self;
    assetsTableView.tag = 7777; // тег для таблицы ассетов
    [containerView addSubview:assetsTableView];
    
    [self.view addSubview:containerView];
}

// сколько времени осталось?
- (NSNumber *)calculateTotalDownloads:(NSArray *)assets {
    if (!assets || ![assets isKindOfClass:[NSArray class]]) {
        return @0;
    }
    
    NSInteger totalDownloads = 0;
    for (NSDictionary *asset in assets) {
        if ([asset isKindOfClass:[NSDictionary class]]) {
            NSNumber *downloadCount = asset[@"download_count"];
            if (downloadCount) {
                totalDownloads += [downloadCount integerValue];
            }
        }
    }
    
    return @(totalDownloads);
}

#pragma mark - File Handling
// открываем файлы
- (void)openFile:(NSDictionary *)file {
    NSString *downloadURL = file[@"download_url"];
    NSString *fileName = file[@"name"];
    
    if (downloadURL) {
        NSURL *url = [NSURL URLWithString:downloadURL];
        
// перезалите видос на github и будет вам счастье
        if ([fileName.lowercaseString hasSuffix:@".mp4"] || [fileName.lowercaseString hasSuffix:@".mov"]) {
            [self showVideoFile:url withTitle:fileName];
            return;
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSData *fileData = [NSData dataWithContentsOfURL:url];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // так, надеюсь ничего не упустил :p
                if ([fileName.lowercaseString hasSuffix:@".jpg"] ||
                    [fileName.lowercaseString hasSuffix:@".jpeg"] ||
                    [fileName.lowercaseString hasSuffix:@".png"] ||
                    [fileName.lowercaseString hasSuffix:@".gif"] ||
                    [fileName.lowercaseString hasSuffix:@".bmp"] ||
                    [fileName.lowercaseString hasSuffix:@".tiff"]) {
                    
                    [self showImageFile:fileData withTitle:fileName];
                }
                // webview
                else if ([fileName.lowercaseString hasSuffix:@".html"] || [fileName.lowercaseString hasSuffix:@".htm"]) {
                    NSString *fileText = fileData ? [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding] : @"Не удалось загрузить файл";
                    [self showHTMLFile:fileText withTitle:fileName];
                }
                // маркдаун проверка
                else if ([fileName.lowercaseString hasSuffix:@".md"] || [fileName.lowercaseString hasSuffix:@".markdown"]) {
                    NSString *fileText = fileData ? [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding] : @"Не удалось загрузить файл";
                    [self showMarkdownFile:fileText withTitle:fileName];
                }
                // plaintext
                else {
                    NSString *fileText = fileData ? [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding] : @"Не удалось загрузить файл"; // мб бинарник
                    [self showPlainTextFile:fileText withTitle:fileName];
                }
            });
        });
    }
}
- (void)showImageFile:(NSData *)imageData withTitle:(NSString *)title {
    if (!imageData) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Ошибка"
                                                        message:@"Не удалось загрузить изображение"
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }
    
    CGRect frame = self.view.bounds;
    
    // я думаю тут все понятно...
    UIView *containerView = [[UIView alloc] initWithFrame:frame];
    containerView.backgroundColor = [UIColor blackColor];
    containerView.tag = 9999;
    
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:frame];
    scrollView.delegate = self;
    scrollView.maximumZoomScale = 5.0;     scrollView.minimumZoomScale = 1.0;
    
    UIImage *image = [UIImage imageWithData:imageData];
    if (image) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        imageView.frame = scrollView.bounds;
        
        [scrollView addSubview:imageView];
        scrollView.contentSize = imageView.frame.size;
    }
    
    [containerView addSubview:scrollView];
    
    UIView *overlayView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 80)];
    overlayView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, frame.size.width - 80, 30)];
    titleLabel.text = title;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textColor = [UIColor whiteColor];
    [overlayView addSubview:titleLabel];
    
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(frame.size.width - 100, 40, 90, 30);
    [closeButton setTitle:@"Закрыть" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeFileView:) forControlEvents:UIControlEventTouchUpInside];
    [overlayView addSubview:closeButton];
    
    [containerView addSubview:overlayView];
    [self.view addSubview:containerView];
}

#pragma mark - UIScrollViewDelegate
// ОПА WEBVIEW!!!!
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return scrollView.subviews.firstObject;
}

- (void)showHTMLFile:(NSString *)htmlContent withTitle:(NSString *)title {
    CGRect frame = self.view.bounds;
    
    UIWebView *webView = [[UIWebView alloc] initWithFrame:frame];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    webView.tag = 9999;
    
    [webView loadHTMLString:htmlContent baseURL:nil];
    
    UIView *overlayView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 80)];
    overlayView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];     overlayView.tag = 9998;
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, frame.size.width - 80, 30)];
    titleLabel.text = title;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [overlayView addSubview:titleLabel];
    
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(frame.size.width - 100, 40, 90, 30);
    [closeButton setTitle:@"Закрыть" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeFileView:) forControlEvents:UIControlEventTouchUpInside];
    [overlayView addSubview:closeButton];
    
    [webView addSubview:overlayView];
    
    [self.view addSubview:webView];
}

//  plaintext
- (void)showPlainTextFile:(NSString *)content withTitle:(NSString *)title {
    CGRect textFrame = self.view.bounds;
    
    UITextView *textView = [[UITextView alloc] initWithFrame:textFrame];
    textView.editable = NO;
    textView.text = content;
    textView.backgroundColor = [UIColor whiteColor];
    textView.font = [UIFont fontWithName:@"Menlo-Regular" size:12]; // красота
    textView.tag = 9999;
    
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(textView.bounds.size.width - 100, 40, 90, 30);
    [closeButton setTitle:@"Закрыть" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeFileView:) forControlEvents:UIControlEventTouchUpInside];
    [textView addSubview:closeButton];
    
    [self.view addSubview:textView];
}

// маркдаун
- (void)showMarkdownFile:(NSString *)markdownContent withTitle:(NSString *)title {
    CGRect frame = self.view.bounds;
    
    UIView *containerView = [[UIView alloc] initWithFrame:frame];
    containerView.backgroundColor = [UIColor whiteColor];
    containerView.tag = 9999;
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, frame.size.width - 80, 30)];
    titleLabel.text = title;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textColor = [UIColor blackColor];
    [containerView addSubview:titleLabel];
    
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(frame.size.width - 100, 40, 90, 30);
    [closeButton setTitle:@"Закрыть" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeFileView:) forControlEvents:UIControlEventTouchUpInside];
    [containerView addSubview:closeButton];
    
    UISegmentedControl *viewModeControl = [[UISegmentedControl alloc] initWithItems:@[@"Рендер", @"Исходник"]];
    viewModeControl.frame = CGRectMake(10, 75, 200, 30);
    viewModeControl.selectedSegmentIndex = 0;
    [viewModeControl addTarget:self action:@selector(switchMarkdownView:) forControlEvents:UIControlEventValueChanged];
    [containerView addSubview:viewModeControl];
    
    UITextView *renderedView = [[UITextView alloc] initWithFrame:CGRectMake(0, 110, frame.size.width, frame.size.height - 110)];
    renderedView.editable = NO;
    renderedView.backgroundColor = [UIColor whiteColor];
    renderedView.tag = 1001;
    
    NSAttributedString *renderedText = [self renderMarkdown:markdownContent];
    renderedView.attributedText = renderedText;
    
    [containerView addSubview:renderedView];
    
    UITextView *sourceView = [[UITextView alloc] initWithFrame:CGRectMake(0, 110, frame.size.width, frame.size.height - 110)];
    sourceView.editable = NO;
    sourceView.text = markdownContent;
    sourceView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];     sourceView.font = [UIFont fontWithName:@"Menlo-Regular" size:12];
    sourceView.tag = 1002;
    sourceView.hidden = YES;
    
    [containerView addSubview:sourceView];
    
    [self.view addSubview:containerView];
}

// переключение между рендером и исходником
- (void)switchMarkdownView:(UISegmentedControl *)control {
    UIView *container = [self.view viewWithTag:9999];
    UIView *renderedView = [container viewWithTag:1001];
    UIView *sourceView = [container viewWithTag:1002];
    
    if (control.selectedSegmentIndex == 0) {
        renderedView.hidden = NO;
        sourceView.hidden = YES;
    } else {
        renderedView.hidden = YES;
        sourceView.hidden = NO;
    }
}

// самая база для маркдауна, а html ставок не будет >:)
- (NSAttributedString *)renderMarkdown:(NSString *)markdown {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    
    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    
    for (NSString *line in lines) {
        NSAttributedString *renderedLine = [self renderMarkdownLine:line];
        [result appendAttributedString:renderedLine];
        
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
    }
    
    return result;
}

- (void)closeAssetsView:(id)sender {
    UIView *containerView = [self.view viewWithTag:8888];
    if (containerView) {
        [containerView removeFromSuperview];
    }
}

- (NSAttributedString *)renderMarkdownLine:(NSString *)line {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if ([trimmedLine hasPrefix:@"# "]) {
        NSString *text = [trimmedLine substringFromIndex:2];
        NSDictionary *attributes = @{
                                     NSFontAttributeName: [UIFont boldSystemFontOfSize:24],
                                     NSForegroundColorAttributeName: [UIColor blackColor]
                                     };
        result = [[NSMutableAttributedString alloc] initWithString:text attributes:attributes];
    }
    else if ([trimmedLine hasPrefix:@"## "]) {
        NSString *text = [trimmedLine substringFromIndex:3];
        NSDictionary *attributes = @{
                                     NSFontAttributeName: [UIFont boldSystemFontOfSize:20],
                                     NSForegroundColorAttributeName: [UIColor blackColor]
                                     };
        result = [[NSMutableAttributedString alloc] initWithString:text attributes:attributes];
    }
    else if ([trimmedLine hasPrefix:@"### "]) {
        NSString *text = [trimmedLine substringFromIndex:4];
        NSDictionary *attributes = @{
                                     NSFontAttributeName: [UIFont boldSystemFontOfSize:18],
                                     NSForegroundColorAttributeName: [UIColor blackColor]
                                     };
        result = [[NSMutableAttributedString alloc] initWithString:text attributes:attributes];
    }
    else if ([self containsPattern:trimmedLine pattern:@"\\*\\*(.+?)\\*\\*"]) {
        result = [self renderBoldText:trimmedLine];
    }
    else if ([self containsPattern:trimmedLine pattern:@"\\*(.+?)\\*"]) {
        result = [self renderItalicText:trimmedLine];
    }
    else if ([self containsPattern:trimmedLine pattern:@"`(.+?)`"]) {
        result = [self renderCodeText:trimmedLine];
    }
    else if ([trimmedLine hasPrefix:@"- "] || [trimmedLine hasPrefix:@"* "]) {
        NSString *text = [@"• " stringByAppendingString:[trimmedLine substringFromIndex:2]];
        NSDictionary *attributes = @{
                                     NSFontAttributeName: [UIFont systemFontOfSize:16],
                                     NSForegroundColorAttributeName: [UIColor blackColor]
                                     };
        result = [[NSMutableAttributedString alloc] initWithString:text attributes:attributes];
    }
    else {
        NSDictionary *attributes = @{
                                     NSFontAttributeName: [UIFont systemFontOfSize:16],
                                     NSForegroundColorAttributeName: [UIColor blackColor]
                                     };
        result = [[NSMutableAttributedString alloc] initWithString:line attributes:attributes];
    }
    
    return result;
}

- (BOOL)containsPattern:(NSString *)string pattern:(NSString *)pattern {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:0
                                                                             error:nil];
    NSRange range = [regex rangeOfFirstMatchInString:string
                                             options:0
                                               range:NSMakeRange(0, string.length)];
    return range.location != NSNotFound;
}

- (NSMutableAttributedString *)renderBoldText:(NSString *)text {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\*\\*(.+?)\\*\\*"
                                                                           options:0
                                                                             error:nil];
    NSArray *matches = [regex matchesInString:text
                                      options:0
                                        range:NSMakeRange(0, text.length)];
    
    NSInteger lastLocation = 0;
    
    for (NSTextCheckingResult *match in matches) {
        if (match.range.location > lastLocation) {
            NSString *normalText = [text substringWithRange:NSMakeRange(lastLocation, match.range.location - lastLocation)];
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:normalText attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16]}]];
        }
        
        NSString *boldText = [text substringWithRange:[match rangeAtIndex:1]];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:boldText attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:16]}]];
        
        lastLocation = match.range.location + match.range.length;
    }
    
    if (lastLocation < text.length) {
        NSString *remainingText = [text substringFromIndex:lastLocation];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:remainingText attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16]}]];
    }
    
    return result;
}

- (NSMutableAttributedString *)renderItalicText:(NSString *)text {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\*(.+?)\\*"
                                                                           options:0
                                                                             error:nil];
    NSArray *matches = [regex matchesInString:text
                                      options:0
                                        range:NSMakeRange(0, text.length)];
    
    NSInteger lastLocation = 0;
    
    for (NSTextCheckingResult *match in matches) {
        if (match.range.location > lastLocation) {
            NSString *normalText = [text substringWithRange:NSMakeRange(lastLocation, match.range.location - lastLocation)];
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:normalText attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16]}]];
        }
        
        NSString *italicText = [text substringWithRange:[match rangeAtIndex:1]];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:italicText attributes:@{NSFontAttributeName: [UIFont italicSystemFontOfSize:16]}]];
        
        lastLocation = match.range.location + match.range.length;
    }
    
    if (lastLocation < text.length) {
        NSString *remainingText = [text substringFromIndex:lastLocation];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:remainingText attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16]}]];
    }
    
    return result;
}

- (NSMutableAttributedString *)renderCodeText:(NSString *)text {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"`(.+?)`"
                                                                           options:0
                                                                             error:nil];
    NSArray *matches = [regex matchesInString:text
                                      options:0
                                        range:NSMakeRange(0, text.length)];
    
    NSInteger lastLocation = 0;
    
    for (NSTextCheckingResult *match in matches) {
        if (match.range.location > lastLocation) {
            NSString *normalText = [text substringWithRange:NSMakeRange(lastLocation, match.range.location - lastLocation)];
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:normalText attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16]}]];
        }
        
        NSString *codeText = [text substringWithRange:[match rangeAtIndex:1]];
        NSDictionary *codeAttributes = @{
                                         NSFontAttributeName: [UIFont fontWithName:@"Menlo-Regular" size:14],
                                         NSBackgroundColorAttributeName: [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0],
                                         NSForegroundColorAttributeName: [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0]
                                         };
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:codeText attributes:codeAttributes]];
        
        lastLocation = match.range.location + match.range.length;
    }
    
    if (lastLocation < text.length) {
        NSString *remainingText = [text substringFromIndex:lastLocation];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:remainingText attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16]}]];
    }
    
    return result;
}

// победа
- (void)closeFileView:(id)sender {
    UIView *fileView = [self.view viewWithTag:9999];
    if (fileView) {
        [fileView removeFromSuperview];
    }
}

#pragma mark - Навигация

- (void)backToPreviousPath {
    if (self.currentPath && self.currentPath.length > 0) {
        self.currentPath = [self.currentPath stringByDeletingLastPathComponent];
        [self fetchRepositoryContents:self.currentRepoName atPath:self.currentPath];
    } else {
        self.showingRepositories = YES;
        self.repoFiles = nil;
        [self.tableView reloadData];
    }
}

- (void)proceedToLargeFolder {
    if (self.pendingFolderName) {
        self.currentPath = [self.currentPath stringByAppendingPathComponent:self.pendingFolderName];
        [self fetchRepositoryContents:self.currentRepoName atPath:self.currentPath];
        self.pendingFolderName = nil;
    }
}

#pragma mark - Warnings
// а вдруг телефон взорветься?
- (void)showWarningForLargeRepo:(NSString *)repoName {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Внимание!"
                                                    message:[NSString stringWithFormat:@"Репозиторий '%@' очень большой и может вызвать проблемы на iOS 6. Продолжить?", repoName]
                                                   delegate:self
                                          cancelButtonTitle:@"Отмена"
                                          otherButtonTitles:@"Продолжить", nil];
    alert.tag = 1001; // тег для идентификации
    [alert show];
}
// надеюсь что не взорветься :p
- (void)showWarningForLargeFolder:(NSString *)folderName {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Внимание!"
                                                    message:[NSString stringWithFormat:@"Папка '%@' содержит очень много файлов и может вызвать вылет приложения. Продолжить?", folderName]
                                                   delegate:self
                                          cancelButtonTitle:@"Отмена"
                                          otherButtonTitles:@"Продолжить", nil];
    alert.tag = 1002; // тег для идентификации
    [alert show];
}

#pragma mark - Alert для ввода username
// оо тут торвальдс приветик!!!!
- (void)showPopupWithTextField {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Введите свой username на GitHub"
                                                        message:nil
                                                       delegate:self
                                              cancelButtonTitle:@"Отмена"
                                              otherButtonTitles:@"OK", nil];
    alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    alertView.tag = 0; // тег для идентификации
    UITextField *textField = [alertView textFieldAtIndex:0];
    textField.placeholder = @"Например: torvalds";
    [alertView show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 0) {
        if (buttonIndex == 1) {
            UITextField *textField = [alertView textFieldAtIndex:0];
            self.username = textField.text;
            
            // наконец не нужно все время вводить имя
            [self saveUsername:self.username];
            
            [self fetchUserData];
            [self fetchRepositories];
        }
    } else if (alertView.tag == 1001) { // предупреждение о большом репо
        if (buttonIndex == 1) {
            [self fetchRepositoryContents:self.currentRepoName atPath:nil];
        }
    } else if (alertView.tag == 1002) { // предупреждение о большой папке
        if (buttonIndex == 1) {
            [self proceedToLargeFolder];
        }
    } else if (alertView.tag == 3001) {
        // открыть в браузере
        if (buttonIndex == 1) {
            if (self.selectedReleaseURL) {
                NSURL *url = [NSURL URLWithString:self.selectedReleaseURL];
                [[UIApplication sharedApplication] openURL:url];
            }
        } else if (buttonIndex == 2) {
            [self showReleaseAssetsForDownload:self.selectedReleaseForDownload];
        }
    } else if (alertView.tag == 3002) {
        // релизы без ассетов
        if (buttonIndex == 1) {
            if (self.selectedReleaseURL) {
                NSURL *url = [NSURL URLWithString:self.selectedReleaseURL];
                [[UIApplication sharedApplication] openURL:url];
            }
        }
    } else if (alertView.tag == 4001) {
        // вы уверены?
        [self handleDownloadConfirmation:buttonIndex];
    }
}


#pragma mark - Profile TableView Helper Methods

- (NSInteger)profileTableViewNumberOfSections {
    return 3; // бог любит троицу
}

- (NSInteger)profileTableViewNumberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1; // аватар и имя
    if (section == 1) return 8; // основная информация
    if (section == 2) return 6; // статистика
    return 0;
}

- (NSString *)profileTableViewTitleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Профиль";
    if (section == 1) return @"Информация";
    if (section == 2) return @"Статистика";
    return nil;
}

- (UITableViewCell *)profileTableViewCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ProfileCellIdentifier = @"ProfileCell";
    UITableViewCell *cell = [self.profiletableView dequeueReusableCellWithIdentifier:ProfileCellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:ProfileCellIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    cell.textLabel.text = @"";
    cell.detailTextLabel.text = @"";
    cell.imageView.image = nil;
    
    if (!self.userInfo) {
        cell.textLabel.text = @"Загрузка...";
        return cell;
    }
    
    if (indexPath.section == 0) {
        // аватар и основное имя
        if (indexPath.row == 0) {
            cell.textLabel.text = self.userInfo[@"name"] != [NSNull null] ? self.userInfo[@"name"] : @"Неизвестно";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"@%@", self.userInfo[@"login"] ?: @""];
            cell.imageView.image = self.userAvatar ?: [UIImage imageNamed:@"placeholder"];
        }
    }
    else if (indexPath.section == 1) {
        // основная информация
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = @"ID";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", self.userInfo[@"id"] ?: @"—"];
                break;
            case 1:
                cell.textLabel.text = @"Тип";
                cell.detailTextLabel.text = self.userInfo[@"type"] ?: @"—";
                break;
            case 2:
                cell.textLabel.text = @"Компания";
                cell.detailTextLabel.text = self.userInfo[@"company"] != [NSNull null] ? self.userInfo[@"company"] : @"—";
                break;
            case 3:
                cell.textLabel.text = @"Блог";
                cell.detailTextLabel.text = self.userInfo[@"blog"] != [NSNull null] ? self.userInfo[@"blog"] : @"—";
                break;
            case 4:
                cell.textLabel.text = @"Местоположение";
                cell.detailTextLabel.text = self.userInfo[@"location"] != [NSNull null] ? self.userInfo[@"location"] : @"—";
                break;
            case 5:
                cell.textLabel.text = @"Email";
                cell.detailTextLabel.text = self.userInfo[@"email"] != [NSNull null] ? self.userInfo[@"email"] : @"—";
                break;
            case 6:
                cell.textLabel.text = @"Bio";
                cell.detailTextLabel.text = self.userInfo[@"bio"] != [NSNull null] ? self.userInfo[@"bio"] : @"—";
                break;
            case 7:
                cell.textLabel.text = @"Создан";
                cell.detailTextLabel.text = [self formatGitHubDate:self.userInfo[@"created_at"]];
                break;
        }
    }
    else if (indexPath.section == 2) {
        // статистика
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = @"Публичные репо";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", self.userInfo[@"public_repos"] ?: @"0"];
                break;
            case 1:
                cell.textLabel.text = @"Приватные репо";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", self.userInfo[@"total_private_repos"] ?: @"—"];
                break;
            case 2:
                cell.textLabel.text = @"Gists";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", self.userInfo[@"public_gists"] ?: @"0"];
                break;
            case 3:
                cell.textLabel.text = @"Подписчики";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", self.userInfo[@"followers"] ?: @"0"];
                break;
            case 4:
                cell.textLabel.text = @"Подписки";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", self.userInfo[@"following"] ?: @"0"];
                break;
            case 5:
                cell.textLabel.text = @"Обновлен";
                cell.detailTextLabel.text = [self formatGitHubDate:self.userInfo[@"updated_at"]];
                break;
        }
    }
    
    return cell;
}

#pragma mark - Profile Helper Methods

- (NSString *)formatGitHubDate:(NSString *)dateString {
    if (!dateString || dateString == (id)[NSNull null]) {
        return @"—";
    }
    
    // GitHub API возвращает даты в формате ISO 8601: 2011-01-25T23:50:35Z
    NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
    [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
    [inputFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    
    NSDate *date = [inputFormatter dateFromString:dateString];
    if (!date) {
        return dateString; // возвращаем как есть если не смогли распарсить
    }
    
    NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
    [outputFormatter setDateFormat:@"dd.MM.yyyy"];
    [outputFormatter setTimeZone:[NSTimeZone localTimeZone]];
    
    return [outputFormatter stringFromDate:date];
}

#pragma mark - Profile TableView Setup

- (void)setupProfileTableView {
    if (self.profiletableView) {
        self.profiletableView.delegate = self;
        self.profiletableView.dataSource = self;
    }
}

// это че такое
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (tableView == self.profiletableView) {
        return [self profileTableViewNumberOfSections];
    }
    return 1;
}

- (void)saveUsername:(NSString *)username {
    if (username && username.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:username forKey:@"GitHubUsername"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (NSString *)loadSavedUsername {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"GitHubUsername"];
}
// да кому нахер это надо?
- (void)showVideoFile:(NSURL *)fileURL withTitle:(NSString *)title {
    MPMoviePlayerController *moviePlayer = [[MPMoviePlayerController alloc] initWithContentURL:fileURL];
    
    [self.view addSubview:moviePlayer.view];
    moviePlayer.view.frame = self.view.bounds;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(moviePlaybackDidFinish:)
                                                 name:MPMoviePlayerPlaybackDidFinishNotification
                                               object:moviePlayer];
    
    [moviePlayer prepareToPlay];
    [moviePlayer play];
}

- (void)moviePlaybackDidFinish:(NSNotification *)notification {
    MPMoviePlayerController *moviePlayer = [notification object];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:MPMoviePlayerPlaybackDidFinishNotification
                                                  object:moviePlayer];
    
    [moviePlayer stop];
    [moviePlayer.view removeFromSuperview];
    
    moviePlayer = nil;
}
#pragma mark - Helper Methods

- (NSString *)formatFileSize:(NSNumber *)sizeInBytes {
    if (!sizeInBytes) return @"";
    double size = [sizeInBytes doubleValue];
    
    if (size < 1024.0) {
        return [NSString stringWithFormat:@"%.0f B", size];
    } else if (size < 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1f KB", size / 1024.0];
    } else if (size < 1024.0 * 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1f MB", size / 1024.0 / 1024.0];
    } else {
        return [NSString stringWithFormat:@"%.1f GB", size / 1024.0 / 1024.0 / 1024.0];
    }
}

@end