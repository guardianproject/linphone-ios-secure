/* ContactDetailsTableViewController.m
 *
 * Copyright (C) 2012  Belledonne Comunications, Grenoble, France
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or   
 *  (at your option) any later version.                                 
 *                                                                      
 *  This program is distributed in the hope that it will be useful,     
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of      
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the       
 *  GNU General Public License for more details.                
 *                                                                      
 *  You should have received a copy of the GNU General Public License   
 *  along with this program; if not, write to the Free Software         
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */ 

#import "ContactDetailsTableViewController.h"
#import "PhoneMainView.h"
#import "UIEditableTableViewCell.h"
#import "UIView+ModalStack.h"
#import "UACellBackgroundView.h"
#import "UILinphone.h"
#import "OrderedDictionary.h"

@interface Entry : NSObject

@property (assign) ABMultiValueIdentifier identifier;

@end

@implementation Entry

@synthesize identifier;

#pragma mark - Lifecycle Functions

- (id)initWithData:(ABMultiValueIdentifier)aidentifier {
    self = [super init];
    if (self != NULL) {
        [self setIdentifier:aidentifier];
    }
    return self;
}

- (void)dealloc {
    [super dealloc];
}

@end


@implementation ContactDetailsTableViewController

@synthesize contact;

#pragma mark - Lifecycle Functions

- (void)initContactDetailsTableViewController {

    dataCache = [[NSMutableArray alloc] init];
    labelArray = [[NSMutableArray alloc] initWithObjects:
                  @"Linphone",
                  [NSString stringWithString:(NSString*)kABPersonPhoneMobileLabel], 
                  [NSString stringWithString:(NSString*)kABPersonPhoneIPhoneLabel],
                  [NSString stringWithString:(NSString*)kABPersonPhoneMainLabel], nil];
    headerController = [[UIContactDetailsHeader alloc] init];
    footerController = [[UIContactDetailsFooter alloc] init];
}

- (id)init {
    self = [super init];
    if (self) {
		[self initContactDetailsTableViewController];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder {
    self = [super initWithCoder:decoder];
    if (self) {
		[self initContactDetailsTableViewController];
	}
    return self;
}	

- (void)dealloc {   
    [labelArray release];
    [dataCache release];
    [headerController release];
    [UIContactDetailsFooter release];
    
    [super dealloc];
}


#pragma mark - ViewController Functions

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView setBackgroundColor:[UIColor clearColor]]; // Can't do it in Xib: issue with ios4
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if(contactDetailsLabelViewController != nil) {
        [[[self view] superview] removeModalView:[contactDetailsLabelViewController view]];
        [editingIndexPath release];
        editingIndexPath = nil;
        [contactDetailsLabelViewController release];
        contactDetailsLabelViewController = nil;
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if(contact != nil && ABRecordGetRecordID(contact) == kABRecordInvalidID) {
        CFRelease(contact);
    }
    contact = nil;
}


#pragma mark -

+ (BOOL)findAndResignFirstResponder:(UIView*)view {
    if (view.isFirstResponder) {
        [view resignFirstResponder];
        return YES;     
    }
    for (UIView *subView in view.subviews) {
        if ([ContactDetailsTableViewController findAndResignFirstResponder:subView])
            return YES;
    }
    return NO;
}

+ (NSString*)localizeLabel:(NSString*)str {
    CFStringRef lLocalizedLabel = ABAddressBookCopyLocalizedLabel((CFStringRef) str);
    NSString * retStr = [NSString stringWithString:(NSString*) lLocalizedLabel];
    CFRelease(lLocalizedLabel);
    return retStr;
}

- (NSDictionary*)getLocalizedLabels {
    OrderedDictionary *dict = [[OrderedDictionary alloc] initWithCapacity:[labelArray count]];
    for(NSString *str in labelArray) {
        [dict setObject:[ContactDetailsTableViewController localizeLabel:str] forKey:str];
    }
    return [dict autorelease];
}

- (void)loadData {
    [dataCache removeAllObjects];
    
    if(contact == NULL) 
        return;
    
    NSLog(@"Load data from contact %p", contact);
    
    // Phone numbers 
    {
        ABMultiValueRef lMap = ABRecordCopyValue(contact, kABPersonPhoneProperty);
        NSMutableArray *subArray = [NSMutableArray array];
        if(lMap) {
            for(int i = 0; i < ABMultiValueGetCount(lMap); ++i) {
                ABMultiValueIdentifier identifier = ABMultiValueGetIdentifierAtIndex(lMap, i);
                Entry *entry = [[Entry alloc] initWithData:identifier];
                [subArray addObject: entry];
                [entry release];
            }
            CFRelease(lMap);
        }
        [dataCache addObject:subArray];
    }
    
    // SIP (IM)
    {
        ABMultiValueRef lMap = ABRecordCopyValue(contact, kABPersonInstantMessageProperty);
        NSMutableArray *subArray = [NSMutableArray array];
        if(lMap) {
            for(int i = 0; i < ABMultiValueGetCount(lMap); ++i) {
                ABMultiValueIdentifier identifier = ABMultiValueGetIdentifierAtIndex(lMap, i);
                CFDictionaryRef lDict = ABMultiValueCopyValueAtIndex(lMap, i);
                if(CFDictionaryContainsKey(lDict, kABPersonInstantMessageServiceKey)) {
                    if(CFStringCompare((CFStringRef)CONTACT_SIP_FIELD, CFDictionaryGetValue(lDict, kABPersonInstantMessageServiceKey), kCFCompareCaseInsensitive) == 0) {
                        Entry *entry = [[Entry alloc] initWithData:identifier];
                        [subArray addObject: entry];
                        [entry release];
                    }
                    CFRelease(lDict);
                }
            }
            CFRelease(lMap);   
        }
        [dataCache addObject:subArray];
    }
    
    [self.tableView reloadData];
}

- (void)addEntry:(UITableView*)tableview section:(NSInteger)section animated:(BOOL)animated {
    [self addEntry:tableview section:section animated:animated value:@""];
}

- (void)addEntry:(UITableView*)tableview section:(NSInteger)section animated:(BOOL)animated value:(NSString *)value{
    NSMutableArray *sectionArray = [dataCache objectAtIndex:section];
    NSUInteger count = [sectionArray count];
    if(section == 0) {
        ABMultiValueIdentifier identifier;
        ABMultiValueRef lcMap = ABRecordCopyValue(contact, kABPersonPhoneProperty);
        ABMutableMultiValueRef lMap;
        if(lcMap != NULL) {
            lMap = ABMultiValueCreateMutableCopy(lcMap);
            CFRelease(lcMap);
        } else {
            lMap = ABMultiValueCreateMutable(kABStringPropertyType);
        }
        CFStringRef label = (CFStringRef)[labelArray objectAtIndex:0];
        ABMultiValueAddValueAndLabel(lMap, [value copy], label, &identifier);
        Entry *entry = [[Entry alloc] initWithData:identifier];
        [sectionArray addObject:entry];
        [entry release];
        
        ABRecordSetValue(contact, kABPersonPhoneProperty, lMap, nil);
        CFRelease(lMap);
    } else if(section == 1) {
        ABMultiValueIdentifier identifier;
        ABMultiValueRef lcMap = ABRecordCopyValue(contact, kABPersonInstantMessageProperty);
        ABMutableMultiValueRef lMap;
        if(lcMap != NULL) {
            lMap = ABMultiValueCreateMutableCopy(lcMap);
            CFRelease(lcMap);
        } else {
            lMap = ABMultiValueCreateMutable(kABDictionaryPropertyType);
        }
        CFStringRef keys[] = {kABPersonInstantMessageUsernameKey,  kABPersonInstantMessageServiceKey};
        CFTypeRef values[] = {[value copy], CONTACT_SIP_FIELD};
        CFDictionaryRef lDict = CFDictionaryCreate(NULL, (const void **)&keys, (const void **)&values, 2, NULL, NULL);
        CFStringRef label = (CFStringRef)[labelArray objectAtIndex:0];
        ABMultiValueAddValueAndLabel(lMap, lDict, label, &identifier);
        CFRelease(lDict);
        Entry *entry = [[Entry alloc] initWithData:identifier];
        [sectionArray addObject:entry];
        [entry release];
        
        ABRecordSetValue(contact, kABPersonInstantMessageProperty, lMap, nil);
        CFRelease(lMap);
    }
    
    if (animated) {
        // Update accessory
        if (count > 0) {
            [tableview reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:count -1 inSection:section]] withRowAnimation:FALSE];
        }
        [tableview insertRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:count inSection:section]] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (void)removeEmptyEntry:(UITableView*)tableview section:(NSInteger)section animated:(BOOL)animated {
    NSMutableArray *sectionDict = [dataCache objectAtIndex: section];
    int row = [sectionDict count] - 1;
    Entry *entry = [sectionDict objectAtIndex:row];
    if(section == 0) {
        ABMultiValueRef lMap = ABRecordCopyValue(contact, kABPersonPhoneProperty);
        int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
        CFStringRef valueRef = ABMultiValueCopyValueAtIndex(lMap, index);
        if(![(NSString*) valueRef length]) {
            [self removeEntry:tableview path:[NSIndexPath indexPathForRow:row inSection:section] animated:animated];
        }
        CFRelease(valueRef);
        CFRelease(lMap);
    } else if(section == 1) {
        ABMultiValueRef lMap = ABRecordCopyValue(contact, kABPersonInstantMessageProperty);
        int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
        CFDictionaryRef lDict = ABMultiValueCopyValueAtIndex(lMap, index);
        CFStringRef valueRef = CFDictionaryGetValue(lDict, kABPersonInstantMessageUsernameKey);
        if(![(NSString*) valueRef length]) {
            [self removeEntry:tableview path:[NSIndexPath indexPathForRow:row inSection:section] animated:animated];
        }
        CFRelease(lDict);
        CFRelease(lMap);
    }
}

- (void)removeEntry:(UITableView*)tableview path:(NSIndexPath*)indexPath animated:(BOOL)animated {
    NSMutableArray *sectionArray = [dataCache objectAtIndex:[indexPath section]];
    Entry *entry = [sectionArray objectAtIndex:[indexPath row]];
    if([indexPath section] == 0) {
        ABMultiValueRef lcMap = ABRecordCopyValue(contact, kABPersonPhoneProperty);
        ABMutableMultiValueRef lMap = ABMultiValueCreateMutableCopy(lcMap);
        CFRelease(lcMap);
        int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
        ABMultiValueRemoveValueAndLabelAtIndex(lMap, index);
        ABRecordSetValue(contact, kABPersonPhoneProperty, lMap, nil);
        CFRelease(lMap);
    } else if([indexPath section] == 1) {
        ABMultiValueRef lcMap = ABRecordCopyValue(contact, kABPersonInstantMessageProperty);
        ABMutableMultiValueRef lMap = ABMultiValueCreateMutableCopy(lcMap);
        CFRelease(lcMap);
        int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
        ABMultiValueRemoveValueAndLabelAtIndex(lMap, index);
        ABRecordSetValue(contact, kABPersonInstantMessageProperty, lMap, nil);
        CFRelease(lMap);
    }
    [sectionArray removeObjectAtIndex:[indexPath row]];
    
    NSArray *tagInsertIndexPath = [NSArray arrayWithObject:indexPath];
    if (animated) {
        [tableview deleteRowsAtIndexPaths:tagInsertIndexPath withRowAnimation:UITableViewRowAnimationFade];
    }
}


#pragma mark - Property Functions

- (void)setContact:(ABRecordRef)acontact {
    self->contact = acontact;
    [self loadData];
}

- (void)addSipField:(NSString*)address {
    [self addEntry:[self tableView] section:1 animated:FALSE value:address];
}


#pragma mark - UITableViewDataSource Functions

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [dataCache count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[dataCache objectAtIndex:section] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kCellId = @"ContactDetailsCell";
    UIEditableTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellId];
    if (cell == nil) {  
        cell = [[[UIEditableTableViewCell alloc] initWithStyle:UITableViewCellStyleValue2 reuseIdentifier:kCellId] autorelease];
        [cell.detailTextField setDelegate:self];
        [cell.detailTextField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
        [cell.detailTextField setAutocorrectionType:UITextAutocorrectionTypeNo];
        
        // Background View
        UACellBackgroundView *selectedBackgroundView = [[[UACellBackgroundView alloc] initWithFrame:CGRectZero] autorelease];
        cell.selectedBackgroundView = selectedBackgroundView;
        [selectedBackgroundView setBackgroundColor:LINPHONE_TABLE_CELL_BACKGROUND_COLOR];
    }
    
    NSMutableArray *sectionDict = [dataCache objectAtIndex:[indexPath section]];
    Entry *entry = [sectionDict objectAtIndex:[indexPath row]];
    
    NSString *value = nil;
    NSString *label = nil;
    
    if([indexPath section] == 0) {
        ABMultiValueRef lMap = ABRecordCopyValue(contact, kABPersonPhoneProperty);
        int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
        CFStringRef labelRef = ABMultiValueCopyLabelAtIndex(lMap, index);
        if(labelRef != NULL) {
            label = [ContactDetailsTableViewController localizeLabel:(NSString*) labelRef];
            CFRelease(labelRef);
        }
        CFStringRef valueRef = ABMultiValueCopyValueAtIndex(lMap, index);
        if(valueRef != NULL) {
            value = [ContactDetailsTableViewController localizeLabel:(NSString*) valueRef];
            CFRelease(valueRef);
        }
        CFRelease(lMap);
    } else if([indexPath section] == 1) {
        ABMultiValueRef lMap = ABRecordCopyValue(contact, kABPersonInstantMessageProperty);
        int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
        CFStringRef labelRef = ABMultiValueCopyLabelAtIndex(lMap, index);
        if(labelRef != NULL) {
            label = [ContactDetailsTableViewController localizeLabel:(NSString*) labelRef];
            CFRelease(labelRef);
        }
        CFDictionaryRef lDict = ABMultiValueCopyValueAtIndex(lMap, index);
        CFStringRef valueRef = CFDictionaryGetValue(lDict, kABPersonInstantMessageUsernameKey);
        if(valueRef != NULL) {
            value = [NSString stringWithString:(NSString*) valueRef];
        }
        CFRelease(lDict);
        CFRelease(lMap);
    }
    [cell.textLabel setText:label];
    [cell.detailTextLabel setText:value];
    [cell.detailTextField setText:value];
    if ([indexPath section] == 0) {
        [cell.detailTextField setKeyboardType:UIKeyboardTypePhonePad];
        [cell.detailTextField setPlaceholder:@"Phone number"];
    } else {
        [cell.detailTextField setKeyboardType:UIKeyboardTypeASCIICapable];
        [cell.detailTextField setPlaceholder:@"SIP address"];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    NSMutableArray *sectionDict = [dataCache objectAtIndex:[indexPath section]];
    Entry *entry  = [sectionDict objectAtIndex:[indexPath row]];
    if (![self isEditing]) {
        NSString *dest;
        if([indexPath section] == 0) {
            ABMultiValueRef lMap = ABRecordCopyValue(contact, kABPersonPhoneProperty);
            int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
            CFStringRef valueRef = ABMultiValueCopyValueAtIndex(lMap, index);
            dest = [ContactDetailsTableViewController localizeLabel:(NSString*) valueRef];
            CFRelease(valueRef);
            CFRelease(lMap);
        } else if([indexPath section] == 1) {
            ABMultiValueRef lMap = ABRecordCopyValue(contact, kABPersonInstantMessageProperty);
            int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
            CFDictionaryRef lDict = ABMultiValueCopyValueAtIndex(lMap, index);
            CFStringRef valueRef = CFDictionaryGetValue(lDict, kABPersonInstantMessageUsernameKey);
            dest = [NSString stringWithString:(NSString*) valueRef];
            CFRelease(lDict);
            CFRelease(lMap);
        }
        if(![dest hasPrefix:@"sip:"]) 
            dest = [NSString stringWithFormat:@"sip:%@", dest];
        CFStringRef lDisplayName = ABRecordCopyCompositeName(contact);
        NSString *displayName = [NSString stringWithString:(NSString*) lDisplayName];
        CFRelease(lDisplayName);
        
        // Go to dialer view
        NSDictionary *dict = [[[NSDictionary alloc] initWithObjectsAndKeys:
                               [[[NSArray alloc] initWithObjects: dest, displayName, nil] autorelease]
                               , @"call:displayName:",
                               nil] autorelease];
        [[PhoneMainView instance] changeView:PhoneView_Dialer dict:dict];
    } else {
        NSString *key;
        if([indexPath section] == 0) {
            ABMultiValueRef lMap = ABRecordCopyValue(contact, kABPersonPhoneProperty);
            int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
            CFStringRef labelRef = ABMultiValueCopyLabelAtIndex(lMap, index);
            key = [NSString stringWithString:(NSString*) labelRef];
            CFRelease(labelRef);
            CFRelease(lMap);
        } else if([indexPath section] == 1) {
            ABMultiValueRef lMap = ABRecordCopyValue(contact, kABPersonInstantMessageProperty);
            int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
            CFStringRef labelRef = ABMultiValueCopyLabelAtIndex(lMap, index);
            key = [NSString stringWithString:(NSString*) labelRef];
            CFRelease(labelRef);
            CFRelease(lMap);
        }
        contactDetailsLabelViewController = [[ContactDetailsLabelViewController alloc] initWithNibName:@"ContactDetailsLabelViewController" 
                                                                                                bundle:[NSBundle mainBundle]];
        [contactDetailsLabelViewController setSelectedData:key];
        [contactDetailsLabelViewController setDataList:[self getLocalizedLabels]];
        [contactDetailsLabelViewController setModalDelegate:self];
        editingIndexPath = [indexPath copy];
        [[[self view] superview] addModalView:[contactDetailsLabelViewController view]];
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath  {
    if (editingStyle == UITableViewCellEditingStyleInsert) {
        [self.tableView beginUpdates];
		[self addEntry:self.tableView section:[indexPath section] animated:TRUE];
        [self.tableView  endUpdates];
	} else if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.tableView beginUpdates];
        [self removeEntry:self.tableView path:indexPath animated:TRUE];
        [self.tableView  endUpdates];
    }
}

#pragma mark - UITableViewDelegate Functions


- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    
    // Resign keyboard
    if(!editing) {
        [ContactDetailsTableViewController findAndResignFirstResponder:[self tableView]];
    }
    
    if(animated) {
        [self.tableView beginUpdates];
    }
    if(editing) {
        for (int section = 0; section <[self numberOfSectionsInTableView:[self tableView]]; ++section) {
            [self addEntry:self.tableView section:section animated:animated];
        }
    } else {
        for (int section = 0; section <[self numberOfSectionsInTableView:[self tableView]]; ++section) {
            [self removeEmptyEntry:self.tableView section:section animated:animated];
        }
    }
    if(animated) {
        [self.tableView endUpdates];
    }


    [headerController setEditing:editing animated:animated];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    int last_index = [[dataCache objectAtIndex:[indexPath section]] count] - 1;
	if (indexPath.row == last_index) {
		return UITableViewCellEditingStyleInsert;
	}
    return UITableViewCellEditingStyleDelete;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {   
    if(section == 0) {
        UIView *headerView = [headerController view];
        [headerController setContact:contact];
        [headerController setEditing:[self isEditing] animated:FALSE];
        return headerView;
    } else {
        return nil;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {   
    if(section != 0) {
        UIView *footerView = [footerController view];
        return footerView;
    } else {
        return nil;
    }
}

- (NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if(section == 0) {
        return nil;
    } else {
        return @"SIP";
    }
}

- (NSString*)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"";
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { 
    if(section == 0) {
        return [UIContactDetailsHeader height:[self isEditing]];
    } else {
        // Hide section if nothing in it
        if([[dataCache objectAtIndex:section] count] > 0)
            return 22;
        else 
            return 0.000001f; // Hack UITableView = 0
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { 
    if(section != 0) {
         return [UIContactDetailsFooter height:[self isEditing]];
    }
    return 0.000001f; // Hack UITableView = 0
}


#pragma mark - UIModalViewDeletage Functions

- (void)modalViewDismiss:(UIModalViewController*)controller value:(id)value {
    [[[self view]superview] removeModalView:[contactDetailsLabelViewController view]];
    contactDetailsLabelViewController = nil;
    if(value != nil) {
        NSMutableArray *sectionDict = [dataCache objectAtIndex:[editingIndexPath section]];
        Entry *entry = [sectionDict objectAtIndex:[editingIndexPath row]];
        if([editingIndexPath section] == 0) {
            ABMultiValueRef lcMap = ABRecordCopyValue(contact, kABPersonPhoneProperty);
            ABMutableMultiValueRef lMap = ABMultiValueCreateMutableCopy(lcMap);
            CFRelease(lcMap);
            int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
            ABMultiValueReplaceLabelAtIndex(lMap, (CFStringRef)((NSString*)value), index);
            ABRecordSetValue(contact, kABPersonPhoneProperty, lMap, nil);
            CFRelease(lMap);
        } else if([editingIndexPath section] == 1) {
            ABMultiValueRef lcMap = ABRecordCopyValue(contact, kABPersonInstantMessageProperty);
            ABMutableMultiValueRef lMap = ABMultiValueCreateMutableCopy(lcMap);
            CFRelease(lcMap);
            int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
            ABMultiValueReplaceLabelAtIndex(lMap, (CFStringRef)((NSString*)value), index);
            ABRecordSetValue(contact, kABPersonInstantMessageProperty, lMap, nil);
            CFRelease(lMap);
        }
        [self.tableView beginUpdates];
        [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject: editingIndexPath] withRowAnimation:FALSE];
        [self.tableView endUpdates];
    }
    [editingIndexPath release];
    editingIndexPath = nil;
}


#pragma mark - UITextFieldDelegate Functions

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];    
    return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField {
    UIView *view = [textField superview]; 
    // Find TableViewCell
    if(view != nil && ![view isKindOfClass:[UIEditableTableViewCell class]]) view = [view superview];
    if(view != nil) {
        UIEditableTableViewCell *cell = (UIEditableTableViewCell*)view;
        NSIndexPath *path = [self.tableView indexPathForCell:cell];
        NSMutableArray *sectionDict = [dataCache objectAtIndex:[path section]];
        Entry *entry = [sectionDict objectAtIndex:[path row]];
        NSString *value = [textField text];
        if([path section] == 0) {
            ABMultiValueRef lcMap = ABRecordCopyValue(contact, kABPersonPhoneProperty);
            ABMutableMultiValueRef lMap = ABMultiValueCreateMutableCopy(lcMap);
            CFRelease(lcMap);
            int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
            ABMultiValueReplaceValueAtIndex(lMap, (CFStringRef)value, index);
            ABRecordSetValue(contact, kABPersonPhoneProperty, lMap, nil);
            CFRelease(lMap);
        } else if([path section] == 1) {
            ABMultiValueRef lcMap = ABRecordCopyValue(contact, kABPersonInstantMessageProperty);
            ABMutableMultiValueRef lMap = ABMultiValueCreateMutableCopy(lcMap);
            CFRelease(lcMap);
            int index = ABMultiValueGetIndexForIdentifier(lMap, [entry identifier]);
            CFStringRef keys[] = { kABPersonInstantMessageUsernameKey,  kABPersonInstantMessageServiceKey};
            CFTypeRef values[] = { [value copy], CONTACT_SIP_FIELD };
            CFDictionaryRef lDict = CFDictionaryCreate(NULL, (const void **)&keys, (const void **)&values, 2, NULL, NULL);
            ABMultiValueReplaceValueAtIndex(lMap, lDict, index);
            CFRelease(lDict);
            ABRecordSetValue(contact, kABPersonInstantMessageProperty, lMap, nil);
            CFRelease(lMap);
        }
        [cell.detailTextLabel setText:value];
    } else {
        NSLog(@"Not valid UIEditableTableViewCell");
    }
    return TRUE;
}

@end