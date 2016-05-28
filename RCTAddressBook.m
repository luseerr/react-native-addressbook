@import AddressBook;
#import <UIKit/UIKit.h>
#import "RCTAddressBook.h"

@implementation RCTAddressBook

RCT_EXPORT_MODULE();

- (NSDictionary *)constantsToExport
{
  return @{
    @"PERMISSION_DENIED": @"denied",
    @"PERMISSION_AUTHORIZED": @"authorized",
    @"PERMISSION_UNDEFINED": @"undefined"
  };
}

RCT_EXPORT_METHOD(checkPermission:(RCTResponseSenderBlock) callback)
{
  int authStatus = ABAddressBookGetAuthorizationStatus();
  if ( authStatus == kABAuthorizationStatusDenied || authStatus == kABAuthorizationStatusRestricted){
    callback(@[[NSNull null], @"denied"]);
  } else if (authStatus == kABAuthorizationStatusAuthorized){
    callback(@[[NSNull null], @"authorized"]);
  } else { //ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusNotDetermined
    callback(@[[NSNull null], @"undefined"]);
  }
}

RCT_EXPORT_METHOD(requestPermission:(RCTResponseSenderBlock) callback)
{
  ABAddressBookRequestAccessWithCompletion(ABAddressBookCreateWithOptions(NULL, nil), ^(bool granted, CFErrorRef error) {
    if (!granted){
      [self checkPermission:callback];
      return;
    }
    [self checkPermission:callback];
  });
}

RCT_EXPORT_METHOD(getContacts:(RCTResponseSenderBlock) callback)
{
  ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);

  int authStatus = ABAddressBookGetAuthorizationStatus();
  if(authStatus != kABAuthorizationStatusAuthorized){
    ABAddressBookRequestAccessWithCompletion(addressBookRef, ^(bool granted, CFErrorRef error) {
      if(granted){
        [self retrieveContactsFromAddressBook:addressBookRef withCallback:callback];
      }else{
        NSDictionary *error = @{
          @"type": @"permissionDenied"
        };
        callback(@[error, [NSNull null]]);
      }
    });
  }
  else{
    [self retrieveContactsFromAddressBook:addressBookRef withCallback:callback];
  }
}

-(void) retrieveContactsFromAddressBook:(ABAddressBookRef)addressBookRef
withCallback:(RCTResponseSenderBlock) callback
{
  NSArray *allContacts = (__bridge_transfer NSArray *)ABAddressBookCopyArrayOfAllPeopleInSourceWithSortOrdering(addressBookRef, NULL, kABPersonSortByLastName);
  int totalContacts = (int)[allContacts count];
  int currentIndex = 0;
  int maxIndex = --totalContacts;

  NSMutableArray *contacts = [[NSMutableArray alloc] init];

  while (currentIndex <= maxIndex){
    NSDictionary *contact = [self dictionaryRepresentationForABPerson: (ABRecordRef)[allContacts objectAtIndex:(long)currentIndex]];

    if(contact){
      [contacts addObject:contact];
    }
    currentIndex++;
  }
  callback(@[[NSNull null], contacts]);
}

-(NSDictionary*) dictionaryRepresentationForABPerson:(ABRecordRef) person
{
  NSMutableDictionary* contact = [NSMutableDictionary dictionary];

  NSNumber *recordID = [NSNumber numberWithInteger:(ABRecordGetRecordID(person))];
  NSString *firstName = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonFirstNameProperty));
  NSString *lastName = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonLastNameProperty));
  NSString *middleName = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonMiddleNameProperty));
  NSString *prefix = (__bridge_transfer NSString *)ABRecordCopyValue(person, kABPersonPrefixProperty);

  [contact setObject: recordID forKey: @"recordID"];

  BOOL hasName = false;
  if (firstName) {
    [contact setObject: firstName forKey:@"firstName"];
    hasName = true;
  }

  if (lastName) {
    [contact setObject: lastName forKey:@"lastName"];
    hasName = true;
  }

  if(middleName){
    [contact setObject: (middleName) ? middleName : @"" forKey:@"middleName"];
  }

  if(!hasName){
    //nameless contact, do not include in results
    return nil;
  }
  
  if(prefix) {
    [contact setObject: prefix forKey:@"prefix"];
  }

  //handle phone numbers
  NSMutableArray *phoneNumbers = [[NSMutableArray alloc] init];

  ABMultiValueRef multiPhones = ABRecordCopyValue(person, kABPersonPhoneProperty);
  for(CFIndex i=0;i<ABMultiValueGetCount(multiPhones);i++) {
    CFStringRef phoneNumberRef = ABMultiValueCopyValueAtIndex(multiPhones, i);
    CFStringRef phoneLabelRef = ABMultiValueCopyLabelAtIndex(multiPhones, i);
    NSString *phoneNumber = (__bridge_transfer NSString *) phoneNumberRef;
    NSString *phoneLabel = (__bridge_transfer NSString *) ABAddressBookCopyLocalizedLabel(phoneLabelRef);
    if(phoneNumberRef){
      CFRelease(phoneNumberRef);
    }
    if(phoneLabelRef){
      CFRelease(phoneLabelRef);
    }
    NSMutableDictionary* phone = [NSMutableDictionary dictionary];
    [phone setObject: phoneNumber forKey:@"number"];
    [phone setObject: phoneLabel forKey:@"label"];
    [phoneNumbers addObject:phone];
  }

  [contact setObject: phoneNumbers forKey:@"phoneNumbers"];
  //end phone numbers

  //handle emails
  NSMutableArray *emailAddreses = [[NSMutableArray alloc] init];

  ABMultiValueRef multiEmails = ABRecordCopyValue(person, kABPersonEmailProperty);
  for(CFIndex i=0;i<ABMultiValueGetCount(multiEmails);i++) {
    CFStringRef emailAddressRef = ABMultiValueCopyValueAtIndex(multiEmails, i);
    CFStringRef emailLabelRef = ABMultiValueCopyLabelAtIndex(multiEmails, i);
    NSString *emailAddress = (__bridge_transfer NSString *) emailAddressRef;
    NSString *emailLabel = (__bridge_transfer NSString *) ABAddressBookCopyLocalizedLabel(emailLabelRef);
    if(emailAddressRef){
      CFRelease(emailAddressRef);
    }
    if(emailLabelRef){
      CFRelease(emailLabelRef);
    }
    NSMutableDictionary* email = [NSMutableDictionary dictionary];
    [email setObject: emailAddress forKey:@"email"];
    [email setObject: emailLabel forKey:@"label"];
    [emailAddreses addObject:email];
  }
  //end emails

  [contact setObject: emailAddreses forKey:@"emailAddresses"];

  [contact setObject: [self getABPersonThumbnailFilepath:person] forKey:@"thumbnailPath"];

  return contact;
}

-(NSString *) getABPersonThumbnailFilepath:(ABRecordRef) person
{
  if (ABPersonHasImageData(person)){

    NSArray *linkedPersons = CFBridgingRelease(ABPersonCopyArrayOfAllLinkedPeople(person));
    for (id obj in linkedPersons) {
        ABRecordRef aLinkedPerson = (__bridge ABRecordRef)obj;
        if (aLinkedPerson == person) {
            continue; // skip the original one
        }
        if (ABPersonHasImageData(aLinkedPerson)) {
            person = aLinkedPerson;
            break;
        }
    }

    CFDataRef photoDataRef = ABPersonCopyImageDataWithFormat(person, kABPersonImageFormatThumbnail);
    if(!photoDataRef){
      return @"";
    }

    NSData* data = (__bridge_transfer NSData*)photoDataRef;
    NSString* tempPath = [NSTemporaryDirectory()stringByStandardizingPath];
    NSError* err = nil;
    NSString* tempfilePath = [NSString stringWithFormat:@"%@/thumbimage_XXXXX", tempPath];
    char template[tempfilePath.length + 1];
    strcpy(template, [tempfilePath cStringUsingEncoding:NSASCIIStringEncoding]);
    mkstemp(template);
    tempfilePath = [[NSFileManager defaultManager]
    stringWithFileSystemRepresentation:template
    length:strlen(template)];

    [data writeToFile:tempfilePath options:NSAtomicWrite error:&err];
    CFRelease(photoDataRef);
    if(!err){
      return tempfilePath;
    }
  }
  return @"";
}

RCT_EXPORT_METHOD(addContact:(NSDictionary *)contactData callback:(RCTResponseSenderBlock)callback)
{
  //@TODO keep addressbookRef in singleton
  ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
  ABRecordRef newPerson = ABPersonCreate();

  CFErrorRef error = NULL;
  ABAddressBookAddRecord(addressBookRef, newPerson, &error);
  //@TODO error handling

  [self updateRecord:newPerson onAddressBook:addressBookRef withData:contactData completionCallback:callback];
}

RCT_EXPORT_METHOD(updateContact:(NSDictionary *)contactData callback:(RCTResponseSenderBlock)callback)
{
  ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
  int recordID = (int)[contactData[@"recordID"] integerValue];
  ABRecordRef record = ABAddressBookGetPersonWithRecordID(addressBookRef, recordID);
  [self updateRecord:record onAddressBook:addressBookRef withData:contactData completionCallback:callback];
}

-(void) updateRecord:(ABRecordRef)record onAddressBook:(ABAddressBookRef)addressBookRef withData:(NSDictionary *)contactData completionCallback:(RCTResponseSenderBlock)callback
{
  CFErrorRef error = NULL;
  NSString *firstName = [contactData valueForKey:@"firstName"];
  NSString *lastName = [contactData valueForKey:@"lastName"];
  NSString *middleName = [contactData valueForKey:@"middleName"];
  NSString *prefix = [contactData valueForKey:@"prefix"];

  ABRecordSetValue(record, kABPersonFirstNameProperty, (__bridge CFStringRef) firstName, &error);
  ABRecordSetValue(record, kABPersonLastNameProperty, (__bridge CFStringRef) lastName, &error);
  ABRecordSetValue(record, kABPersonMiddleNameProperty, (__bridge CFStringRef) middleName, &error);
  ABRecordSetValue(record, kABPersonPrefixProperty, (__bridge CFStringRef) prefix, &error);


  ABMutableMultiValueRef multiPhone = ABMultiValueCreateMutable(kABMultiStringPropertyType);
  NSArray* phoneNumbers = [contactData valueForKey:@"phoneNumbers"];
  for (id phoneData in phoneNumbers) {
    NSString *label = [phoneData valueForKey:@"label"];
    NSString *number = [phoneData valueForKey:@"number"];

    if ([label isEqual: @"main"]){
      ABMultiValueAddValueAndLabel(multiPhone, (__bridge CFStringRef) number, kABPersonPhoneMainLabel, NULL);
    }
    else if ([label isEqual: @"mobile"]){
      ABMultiValueAddValueAndLabel(multiPhone, (__bridge CFStringRef) number, kABPersonPhoneMobileLabel, NULL);
    }
    else if ([label isEqual: @"iPhone"]){
      ABMultiValueAddValueAndLabel(multiPhone, (__bridge CFStringRef) number, kABPersonPhoneIPhoneLabel, NULL);
    }
    else{
      ABMultiValueAddValueAndLabel(multiPhone, (__bridge CFStringRef) number, (__bridge CFStringRef) label, NULL);
    }
  }
  ABRecordSetValue(record, kABPersonPhoneProperty, multiPhone, nil);
  CFRelease(multiPhone);

  ABMutableMultiValueRef multiEmail = ABMultiValueCreateMutable(kABMultiStringPropertyType);
  NSArray* emails = [contactData valueForKey:@"emailAddresses"];
  for (id emailData in emails) {
    NSString *label = [emailData valueForKey:@"label"];
    NSString *email = [emailData valueForKey:@"email"];

    ABMultiValueAddValueAndLabel(multiEmail, (__bridge CFStringRef) email, (__bridge CFStringRef) label, NULL);
  }
  ABRecordSetValue(record, kABPersonEmailProperty, multiEmail, nil);
  CFRelease(multiEmail);

  ABAddressBookSave(addressBookRef, &error);
  if (error != NULL)
  {
    CFStringRef errorDesc = CFErrorCopyDescription(error);
    NSString *nsErrorString = (__bridge NSString *)errorDesc;
    callback(@[nsErrorString]);
    CFRelease(errorDesc);
  }
  else{
    callback(@[[NSNull null]]);
  }
}

RCT_EXPORT_METHOD(deleteContact:(NSDictionary *)contactData callback:(RCTResponseSenderBlock)callback)
{
  CFErrorRef error = NULL;
  ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
  int recordID = (int)[contactData[@"recordID"] integerValue];
  ABRecordRef record = ABAddressBookGetPersonWithRecordID(addressBookRef, recordID);
  ABAddressBookRemoveRecord(addressBookRef, record, &error);
  ABAddressBookSave(addressBookRef, &error);
  //@TODO handle error
  callback(@[[NSNull null], [NSNull null]]);
}

@end
