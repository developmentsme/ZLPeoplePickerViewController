//
//  ZLPeoplePickerViewController.m
//  ZLPeoplePickerViewControllerDemo
//
//  Created by Zhixuan Lai on 11/4/14.
//  Copyright (c) 2014 Zhixuan Lai. All rights reserved.
//

#import "ZLPeoplePickerViewController.h"
#import "ZLResultsTableViewController.h"
#import "LRIndexedCollationWithSearch.h"

#import <AddressBook/AddressBook.h>
#import <AddressBookUI/AddressBookUI.h>

#import "APAddressBook.h"
#import "APContact.h"
#import "APContact+Sorting.h"

@interface ZLPeoplePickerViewController () <ABPeoplePickerNavigationControllerDelegate,ABPersonViewControllerDelegate, ABNewPersonViewControllerDelegate, ABUnknownPersonViewControllerDelegate, UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating>

@property (strong, nonatomic) APAddressBook *addressBook;
@property (strong, nonatomic) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UISearchController *searchController;
@property (strong, nonatomic) ZLResultsTableViewController *resultsTableViewController;

// for state restoration
@property BOOL searchControllerWasActive;
@property BOOL searchControllerSearchFieldWasFirstResponder;

@end

@implementation ZLPeoplePickerViewController
- (instancetype)initWithType:(ZLPeoplePickerViewControllerType)type {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        [self setup];
        _type = type;
    }
    return self;
}

- (void)setup {
    self.addressBook = [[APAddressBook alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _resultsTableViewController = [[ZLResultsTableViewController alloc] init];
    _searchController = [[UISearchController alloc] initWithSearchResultsController:self.resultsTableViewController];
    self.searchController.searchResultsUpdater = self;
    [self.searchController.searchBar sizeToFit];
    self.tableView.tableHeaderView = self.searchController.searchBar;
    
    // we want to be the delegate for our filtered table so didSelectRowAtIndexPath is called for both tables
    self.resultsTableViewController.tableView.delegate = self;
    self.searchController.delegate = self;
//    self.searchController.dimsBackgroundDuringPresentation = NO; // default is YES
    self.searchController.searchBar.delegate = self; // so we can monitor text changes + others
    
    // Search is now just presenting a view controller. As such, normal view controller
    // presentation semantics apply. Namely that presentation will walk up the view controller
    // hierarchy until it finds the root view controller or one that defines a presentation context.
    //
    self.definesPresentationContext = YES;  // know where you want UISearchController to be displayed
    
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.tableView addSubview:self.refreshControl];
    [self.refreshControl addTarget:self action:@selector(refreshControlAction:) forControlEvents:UIControlEventValueChanged];

    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    self.navigationItem.title = @"Contacts";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(showNewPersonViewController)];
    
    [self refreshControlAction:self.refreshControl];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // restore the searchController's active state
    if (self.searchControllerWasActive) {
        self.searchController.active = self.searchControllerWasActive;
        _searchControllerWasActive = NO;
        
        if (self.searchControllerSearchFieldWasFirstResponder) {
            [self.searchController.searchBar becomeFirstResponder];
            _searchControllerSearchFieldWasFirstResponder = NO;
        }
    }
}

//- (void)didMoveToParentViewController:(UIViewController *)parent {
//    if (![parent isEqual:self.parentViewController]) {
//        if (self.delegate && [self.delegate respondsToSelector:@selector(peoplePickerViewControllerTypeSingleDidReturn:)]) {
//            [self.delegate peoplePickerViewControllerTypeSingleDidReturn:self];
//        }
//    }
//}

#pragma mark - Action
+ (void)presentPeoplePickerViewControllerWithType:(ZLPeoplePickerViewControllerType)type forParentViewController:(UIViewController *)parentViewController {
    UINavigationController *navController = [[UINavigationController alloc] init];
    ZLPeoplePickerViewController *peoplePicker = [[ZLPeoplePickerViewController alloc] initWithType:type];
    [navController pushViewController:peoplePicker animated:NO];
    peoplePicker.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:peoplePicker action:@selector(doneButtonAction:)];
    peoplePicker.delegate = parentViewController;
    [parentViewController presentViewController:navController animated:YES completion:nil];
}

- (void)doneButtonAction:(id)sender {
    if (self.delegate && [self.delegate respondsToSelector:@selector(peoplePickerViewControllerTypeMultiple:didReturnWithSelectedPeople:)]) {
        [self.delegate peoplePickerViewControllerTypeMultiple:self didReturnWithSelectedPeople: [self.selectedPeople copy]];
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)refreshControlAction:(UIRefreshControl *)aRefreshControl {
    [aRefreshControl beginRefreshing];
    [self reloadData:^(BOOL succeeded, NSError *error) {
        [aRefreshControl endRefreshing];
    }];
}

- (void)reloadData {
    [self reloadData:nil];
}

- (void)reloadData:(void (^)(BOOL succeeded, NSError *error))completionBlock {
    __weak __typeof(self) weakSelf = self;
    [self loadContacts:^(BOOL succeeded, NSError *error) {
        if (!error) {
            [weakSelf.tableView reloadData];
            completionBlock(YES,nil);
        } else {
            completionBlock(NO,nil);
        }
    }];
}


#pragma mark - UISearchBarDelegate

- (void)searchBarCancelButtonClicked:(UISearchBar *) aSearchBar {
    [aSearchBar resignFirstResponder];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)aSearchBar {
    [aSearchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)aSearchBar {
    [aSearchBar setShowsCancelButton:NO animated:YES];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    APContact *contact = [self contactForRowAtIndexPath:indexPath];
    if (self.delegate && [self.delegate respondsToSelector:@selector(peoplePickerViewControllerTypeSingle:didSelectPerson:)]) {
        [self.delegate peoplePickerViewControllerTypeSingle:self didSelectPerson:contact.recordID];
    }
    
    if (self.type == ZLPeoplePickerViewControllerTypeMultiple) {
        if ([self.selectedPeople containsObject:contact.recordID]) {
            [self.selectedPeople removeObject:contact.recordID];
        } else {
            [self.selectedPeople addObject:contact.recordID];
        }
    }
    
    [self.tableView reloadData];
}


#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    // update the filtered array based on the search text
    NSString *searchText = searchController.searchBar.text;
    NSMutableArray *searchResults = [[self.partitionedContacts valueForKeyPath:@"@unionOfArrays.self" ] mutableCopy];
    
    // strip out all the leading and trailing spaces
    NSString *strippedStr = [searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    // break up the search terms (separated by spaces)
    NSArray *searchItems = nil;
    if (strippedStr.length > 0) {
        searchItems = [strippedStr componentsSeparatedByString:@" "];
    }
    // build all the "AND" expressions for each value in the searchString
    //
    NSMutableArray *andMatchPredicates = [NSMutableArray array];
    
    for (NSString *searchString in searchItems) {
        // each searchString creates an OR predicate for: name, yearIntroduced, introPrice
        //
        // example if searchItems contains "iphone 599 2007":
        //      name CONTAINS[c] "iphone"
        //      name CONTAINS[c] "599", yearIntroduced ==[c] 599, introPrice ==[c] 599
        //      name CONTAINS[c] "2007", yearIntroduced ==[c] 2007, introPrice ==[c] 2007
        //
        NSMutableArray *searchItemsPredicate = [NSMutableArray array];
        
        // TODO: match phone number matching

        // name field matching
        NSPredicate *finalPredicate = [NSPredicate predicateWithFormat:@"compositeName CONTAINS[c] %@", searchString];
        [searchItemsPredicate addObject:finalPredicate];
        
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"ANY SELF.emails CONTAINS[c] %@", searchString];
        [searchItemsPredicate addObject:predicate];

        predicate = [NSPredicate predicateWithFormat:@"ANY SELF.addresses.street CONTAINS[c] %@", searchString];
        [searchItemsPredicate addObject:predicate];
        predicate = [NSPredicate predicateWithFormat:@"ANY SELF.addresses.city CONTAINS[c] %@", searchString];
        [searchItemsPredicate addObject:predicate];
        predicate = [NSPredicate predicateWithFormat:@"ANY SELF.addresses.zip CONTAINS[c] %@", searchString];
        [searchItemsPredicate addObject:predicate];
        predicate = [NSPredicate predicateWithFormat:@"ANY SELF.addresses.country CONTAINS[c] %@", searchString];
        [searchItemsPredicate addObject:predicate];
        predicate = [NSPredicate predicateWithFormat:@"ANY SELF.addresses.countryCode CONTAINS[c] %@", searchString];
        [searchItemsPredicate addObject:predicate];

//        NSNumberFormatter *numFormatter = [[NSNumberFormatter alloc] init];
//        [numFormatter setNumberStyle:NSNumberFormatterNoStyle];
//        NSNumber *targetNumber = [numFormatter numberFromString:searchString];
//        if (targetNumber != nil) {   // searchString may not convert to a number
//            predicate = [NSPredicate predicateWithFormat:@"ANY SELF.sanitizePhones CONTAINS[c] %@", searchString];
//            [searchItemsPredicate addObject:predicate];
//        }
        
        // at this OR predicate to our master AND predicate
        NSCompoundPredicate *orMatchPredicates = (NSCompoundPredicate *)[NSCompoundPredicate orPredicateWithSubpredicates:searchItemsPredicate];
        [andMatchPredicates addObject:orMatchPredicates];
    }
    
    NSCompoundPredicate *finalCompoundPredicate = nil;
    
    // match up the fields of the Product object
    finalCompoundPredicate =
    (NSCompoundPredicate *)[NSCompoundPredicate andPredicateWithSubpredicates:andMatchPredicates];
    
    searchResults = [[searchResults filteredArrayUsingPredicate:finalCompoundPredicate] mutableCopy];
    
    // hand over the filtered results to our search results table
    ZLResultsTableViewController *tableController = (ZLResultsTableViewController *)self.searchController.searchResultsController;
    [tableController setPartitionedContactsWithContacts: searchResults];
    [tableController.tableView reloadData];
}

#pragma mark - APAddressBook

- (void)loadContacts:(void (^)(BOOL succeeded, NSError *error))completionBlock {
    __weak __typeof(self) weakSelf = self;
    self.addressBook.fieldsMask = APContactFieldFirstName | APContactFieldLastName | APContactFieldCompositeName | APContactFieldPhones | APContactFieldThumbnail |APContactFieldRecordID |APContactFieldEmails |APContactFieldAddresses;
    self.addressBook.filterBlock = ^BOOL(APContact *contact)
    {
        return contact.phones.count > 0 && contact.compositeName != nil;
    };
    [self.addressBook loadContacts:^(NSArray *contacts, NSError *error) {
        if (!error)
        {
            [weakSelf setPartitionedContactsWithContacts:contacts];
            if (completionBlock) {
                completionBlock(YES,nil);
            }
        }
        else {
            if (completionBlock) {
                completionBlock(NO,error);
            }
        }
    }];
    [self.addressBook startObserveChangesWithCallback:^{
                  NSLog(@"Address book changed!");
        [weakSelf reloadData];
    }];
}

#pragma mark - ABAdressBookUI

#pragma mark Create a new person
// Called when users tap "Create New Contact" in the application. Allows users to create a new contact.
-(void)showNewPersonViewController
{
    ABNewPersonViewController *picker = [[ABNewPersonViewController alloc] init];
    picker.newPersonViewDelegate = self;
    
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:navigation animated:YES completion:nil];
}
#pragma mark ABNewPersonViewControllerDelegate methods
// Dismisses the new-person view controller.
- (void)newPersonViewController:(ABNewPersonViewController *)newPersonViewController didCompleteWithNewPerson:(ABRecordRef)person
{
    [self dismissViewControllerAnimated:YES completion:NULL];
}

@end