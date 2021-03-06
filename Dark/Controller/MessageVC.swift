//
//  MessageViewController.swift
//  Dark
//
//  Created by surendra kumar on 10/7/17.
//  Copyright © 2017 weza. All rights reserved.
//

// TODO: Image is not loading second time
import UIKit
import  JSQMessagesViewController
import Firebase
import FirebaseDatabase

 struct ChatMetaData : Codable{
    var timeStamp  : Int
    var recieverID : String
}

 enum MessageItem : String{
    case senderId
    case senderName
    case text
    case photoURL
}
private enum URLPrefix : String{
    case gs = "gs://"
}
private let emptyPhotoURL = ""
class MessageViewController: JSQMessagesViewController {
    
  
    private lazy var messageRef: DatabaseReference = REF_CHAT.child("\(String(describing: convID!))").child(DARKFirebaseNode.messages.rawValue)
    private lazy var isNewMessageRef : DatabaseReference =  REF_CHAT.child("\(String(describing: convID!))").child(DARKFirebaseNode.newMessage.rawValue)
    private lazy var isUserTypingRef : DatabaseReference = REF_CHAT.child(self.convID!).child(DARKFirebaseNode.isUserTyping.rawValue).child(self.senderId)
    private lazy var userTypingQuery : DatabaseQuery = REF_CHAT.child(self.convID!).child(DARKFirebaseNode.isUserTyping.rawValue).queryOrderedByValue().queryEqual(toValue: true)
    private lazy var outgoingBubbleImageView: JSQMessagesBubbleImage = self.setupOutgoingBubble()
    private lazy var incomingBubbleImageView: JSQMessagesBubbleImage = self.setupIncomingBubble()
    
    private var localtyping = false
    private let uid = Auth.auth().currentUser?.uid
    private var isRunOneTime : Bool = false
    private var imagePicker : UIImagePickerController!
    private var photoMessageMap = [String : JSQPhotoMediaItem]()
    private var messages = [JSQMessage]()
    public  var recieverID : String?
    public  var convID : String?
   
    private var isTyping : Bool {
            get{
            return localtyping
            }
            set{
            localtyping = newValue
                isUserTypingRef.setValue(newValue)
            }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
         title = self.senderDisplayName
        // No avatars
        collectionView!.collectionViewLayout.incomingAvatarViewSize = CGSize.zero
        collectionView!.collectionViewLayout.outgoingAvatarViewSize = CGSize.zero
        let lb = UIButton(frame: CGRect(x: 10, y: 30, width: 100, height: 45))
        lb.setTitle("back", for: .normal)
        lb.setTitleColor(UIColor.blue, for: .normal)
        lb.addTarget(self, action: #selector(targetbutton), for: .touchUpInside)
        self.view.insertSubview(lb, at: 1)
        // Method
        self.InitialiseConversationID()
        finishReceivingMessage()
        self.observeMessages()
        //picker
        imagePicker = self.setUpImagePicker(delegateProvider: self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.obeserveTyping()
        
    }
    
    @objc func targetbutton(){
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func dis(_ sender: Any) {
         self.dismiss(animated: true, completion: nil)
    }
    
    func InitialiseConversationID(){
        guard convID == nil else {return}
        let senderID5 = String(senderId.characters.prefix(5))
        let recieverID5 = String(recieverID!.characters.prefix(5))
        if (senderID5 > recieverID5){
            self.convID = senderID5 + recieverID5
        }else{
            self.convID = recieverID5 + senderID5
        }
    }
    private func setupOutgoingBubble() -> JSQMessagesBubbleImage {
        let bubbleImageFactory = JSQMessagesBubbleImageFactory()
        return bubbleImageFactory!.outgoingMessagesBubbleImage(with: UIColor.jsq_messageBubbleRed())
    }
    
    private func setupIncomingBubble() -> JSQMessagesBubbleImage {
        let bubbleImageFactory = JSQMessagesBubbleImageFactory()
        return bubbleImageFactory!.incomingMessagesBubbleImage(with: UIColor.jsq_messageBubbleLightGray())
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageDataForItemAt indexPath: IndexPath!) -> JSQMessageData! {
        return messages[indexPath.item]
    }
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return messages.count
    }
   
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageBubbleImageDataForItemAt indexPath: IndexPath!) -> JSQMessageBubbleImageDataSource! {
        let message = messages[indexPath.item]
        if message.senderId == senderId {
            return outgoingBubbleImageView
        }else{
            return incomingBubbleImageView
        }
    }

    override func collectionView(_ collectionView: JSQMessagesCollectionView!, avatarImageDataForItemAt indexPath: IndexPath!) -> JSQMessageAvatarImageDataSource! {
        return nil
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = super.collectionView(collectionView, cellForItemAt: indexPath) as! JSQMessagesCollectionViewCell
        let message = messages[indexPath.item]
        
        if message.senderId == senderId {
            cell.textView?.textColor = UIColor.white
        } else {
            cell.textView?.textColor = UIColor.black
        }
        return cell
    }
    
    private func addMessage(withId id: String, name: String, text: String) {
        if let message = JSQMessage(senderId: id, displayName: name, text: text) {
            messages.append(message)
        }
    }
    
    private func addPhotoMessage(withID id : String, key : String , mediaItem : JSQPhotoMediaItem){
        if let message = JSQMessage(senderId: id, displayName: "", media: mediaItem){
            messages.append(message)
            if (mediaItem.image == nil){
                photoMessageMap[key] = mediaItem
            }
            collectionView.reloadData()
        }
    }
    
    override func didPressAccessoryButton(_ sender: UIButton!) {
        self.present(imagePicker, animated: true, completion: nil)
    }
    
    override func didPressSend(_ button: UIButton!, withMessageText text: String!, senderId: String!, senderDisplayName: String!, date: Date!) {
        self.sendNewMessage(text: text)
        self.setNewMessageBadge()
        self.setNewConversation()
        finishSendingMessage()
        self.isTyping = false
        JSQSystemSoundPlayer.jsq_playMessageSentSound()
    }
    
    func sendNewMessage(text : String){
        let itemRef = messageRef.childByAutoId()
        let messageItem = [
            MessageItem.senderId.rawValue: senderId,
            MessageItem.senderName.rawValue: senderDisplayName!,
            MessageItem.text.rawValue: text,
            ]
        Messages.sharedInstanse.createMessage(ref: itemRef, message: messageItem)
    }
    
    func setNewMessageBadge(){
        let isNewMessageData = ["\(self.senderId!)" : false , "\(self.recieverID!)": true ]
        MessageStatus.sharedInstanse.setNewMessageBadgeforReciever(newMessgeBadgeRef: isNewMessageRef, data: isNewMessageData)
    }
    
    func setNewConversation(){
        let senderChatref = REF_USER.child(senderId).child(DARKFirebaseNode.userchatList.rawValue).child(self.convID!)
        let recieverChatref = REF_USER.child(recieverID!).child(DARKFirebaseNode.userchatList.rawValue).child(self.convID!)
        let serderChatMetaData = ChatMetaData(timeStamp: Int(Date().timeIntervalSince1970), recieverID: self.recieverID!)
        let recieverChatMetaData = ChatMetaData(timeStamp: Int(Date().timeIntervalSince1970), recieverID: self.senderId!)
        do {
            try Conversation.sharedInstanse.setNewConversation(recieverHandle: recieverChatref, senderHandle: senderChatref, senderChatData: serderChatMetaData, recieverChatData: recieverChatMetaData)
        }catch{
            print(error.localizedDescription)
        }
    }
    
    private func observeMessages() {
        
        Messages.sharedInstanse.getAllMessagesofKey(messageRef: messageRef) { messageData,key in
            if let id = messageData[MessageItem.senderId.rawValue] as String!, let name = messageData[MessageItem.senderName.rawValue] as String!, let text = messageData[MessageItem.text.rawValue] as String!, text.characters.count > 0 {
                self.addMessage(withId: id, name: name, text: text)
                self.finishReceivingMessage()
              // Decode if message 
            }else if let id = messageData[MessageItem.senderId.rawValue] as String!,
                let photoURL = messageData[MessageItem.photoURL.rawValue] as String! {
                if let mediaItem = JSQPhotoMediaItem(maskAsOutgoing: id == self.senderId) {
                    self.addPhotoMessage(withID: id, key: key, mediaItem: mediaItem)
                    if photoURL.hasPrefix(URLPrefix.gs.rawValue) {
                        self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: nil)
                    }
                }
            }
        }
        
        Messages.sharedInstanse.updatedImageMessageforKey(messageRef: messageRef) { (messageData, key) in
            if let photoURL = messageData[MessageItem.photoURL.rawValue] as String! {
                // The photo has been updated.
                if let mediaItem = self.photoMessageMap[key] {
                    self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: key)
                }
            }
        }
    }
    
    override func textViewDidChange(_ textView: UITextView) {
        super.textViewDidChange(textView)
        isTyping = textView.text != ""
        
    }
    func obeserveTyping(){
     self.isUserTypingRef.onDisconnectRemoveValue()

        MessageStatus.sharedInstanse.isUserTyping(typingquery: userTypingQuery) { typingCount in
            if typingCount == 1 && self.isTyping == true {return}
                        self.showTypingIndicator = typingCount > 0
                        self.scrollToBottom(animated: true)
        }
    }

}

extension MessageViewController{
    
    func sendPhotoMessage() -> String? {
        let isNewMessageData = ["\(self.senderId!)" : false , "\(self.recieverID!)": true ]
        self.isNewMessageRef.setValue(isNewMessageData)
        let itemRef = messageRef.childByAutoId()
        let messageItem =  [
            MessageItem.photoURL.rawValue: emptyPhotoURL,
            MessageItem.senderId.rawValue: senderId!
            ]
        itemRef.setValue(messageItem){
            error, ref in
            self.setNewConversation()
        }
        
        finishSendingMessage()
        return itemRef.key
    }
    
    func setImageURL(url : String ,forPhotoMessageWithKey key : String){
        let itemRef = messageRef.child(key)
        itemRef.updateChildValues([MessageItem.photoURL.rawValue: url])
    }
    
    private func fetchImageDataAtURL(_ photoURL: String, forMediaItem mediaItem: JSQPhotoMediaItem, clearsPhotoMessageMapOnSuccessForKey key: String?) {
        let storageRef = Storage.storage().reference(forURL: photoURL)
        storageRef.getData(maxSize: INT64_MAX){ (data, error) in
            if let error = error {
                print("Error downloading image data: \(error)")
                return
            }
            mediaItem.image = UIImage.init(data: data!)
            self.collectionView.reloadData()
            guard key != nil else {return}
            self.photoMessageMap.removeValue(forKey: key!)
        }
    }
}

extension MessageViewController : UINavigationControllerDelegate, UIImagePickerControllerDelegate, UIPopoverPresentationControllerDelegate{
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
        
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        // Image URL
        if let imageURL = info[UIImagePickerControllerImageURL] {
            if let key = self.sendPhotoMessage(){
                REF_STORAGE.child(senderId).putFile(from: imageURL as! URL, metadata: nil, completion: { metadata, error in
                    if error != nil {return}
                    self.setImageURL(url: (metadata?.downloadURL()?.absoluteString)!, forPhotoMessageWithKey: key)
                })
            }
        }
        picker.dismiss(animated: true, completion: nil)
    }
    
    
}

