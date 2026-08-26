import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/services/app_logger.dart';


// Mock User data
class MockUser {
  final String id;
  final String username;
  final String displayName;
  final String email;
  final String profileImageUrl;
  final String coverImageUrl;
  final String bio;
  final bool isVerified;
  final DateTime joinDate;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final String publicKey;
  final String? privateKey; // Only stored for mock purposes

  MockUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.email,
    required this.profileImageUrl,
    required this.coverImageUrl,
    required this.bio,
    required this.isVerified,
    required this.joinDate,
    required this.followersCount,
    required this.followingCount,
    required this.postsCount,
    required this.publicKey,
    this.privateKey,
  });
}

// Mock Post data
class MockPost {
  final String id;
  final String userId;
  final String content;
  final List<String> mediaUrls;
  final DateTime createdAt;
  final int likesCount;
  final int commentsCount;
  final int repostsCount;
  final bool isLiked;
  final bool isReposted;
  final List<MockComment>? comments;

  MockPost({
    required this.id,
    required this.userId,
    required this.content,
    required this.mediaUrls,
    required this.createdAt,
    required this.likesCount,
    required this.commentsCount,
    required this.repostsCount,
    this.isLiked = false,
    this.isReposted = false,
    this.comments,
  });
}

// Mock Comment data
class MockComment {
  final String id;
  final String userId;
  final String content;
  final DateTime createdAt;
  final int likesCount;
  final int repliesCount;

  MockComment({
    required this.id,
    required this.userId,
    required this.content,
    required this.createdAt,
    required this.likesCount,
    required this.repliesCount,
  });
}

// Mock Notification data
class MockNotification {
  final String id;
  final String userId; // User who triggered the notification
  final NotificationType type;
  final String? postId;
  final String? commentId;
  final DateTime createdAt;
  final bool isRead;

  MockNotification({
    required this.id,
    required this.userId,
    required this.type,
    this.postId,
    this.commentId,
    required this.createdAt,
    this.isRead = false,
  });
}

enum NotificationType {
  like,
  comment,
  repost,
  follow,
  mention,
}

// Mock data sets
class MockData {
  // Ensure mock data is initialized by calling this method
  static void initialize() {
    // This ensures the lists are accessible
    AppLogger.log("Mock data initialized with ${users.length} users");
  }
  
  // Users
  static final List<MockUser> users = [
    MockUser(
      id: 'user1',
      username: 'john_doe',
      displayName: 'John Doe',
      email: 'john@example.com',
      profileImageUrl: 'https://randomuser.me/api/portraits/men/1.jpg',
      coverImageUrl: 'https://picsum.photos/800/200?random=1',
      bio: 'Building decentralized social networks with Deltanium blockchain',
      isVerified: true,
      joinDate: DateTime(2023, 6, 15),
      followersCount: 243,
      followingCount: 128,
      postsCount: 5,
      publicKey: 'abc123publickey',
      privateKey: 'abc123privatekey',
    ),
    MockUser(
      id: 'user2',
      username: 'alice_web3',
      displayName: 'Alice',
      email: 'alice@example.com',
      profileImageUrl: 'https://randomuser.me/api/portraits/women/2.jpg',
      coverImageUrl: 'https://picsum.photos/800/200?random=2',
      bio: 'Blockchain developer | Web3 enthusiast | Coffee lover',
      isVerified: true,
      joinDate: DateTime(2023, 4, 10),
      followersCount: 548,
      followingCount: 231,
      postsCount: 87,
      publicKey: 'def456publickey',
      privateKey: 'def456privatekey',
    ),
    MockUser(
      id: 'user3',
      username: 'bob_crypto',
      displayName: 'Bob',
      email: 'bob@example.com',
      profileImageUrl: 'https://randomuser.me/api/portraits/men/3.jpg',
      coverImageUrl: 'https://picsum.photos/800/200?random=3',
      bio: 'Crypto enthusiast | NFT collector | Building the future',
      isVerified: false,
      joinDate: DateTime(2023, 7, 22),
      followersCount: 112,
      followingCount: 283,
      postsCount: 42,
      publicKey: 'ghi789publickey',
      privateKey: 'ghi789privatekey',
    ),
    MockUser(
      id: 'user4',
      username: 'sarah_dev',
      displayName: 'Sarah',
      email: 'sarah@example.com',
      profileImageUrl: 'https://randomuser.me/api/portraits/women/4.jpg',
      coverImageUrl: 'https://picsum.photos/800/200?random=4',
      bio: 'Full-stack developer | Open source contributor | Dog lover',
      isVerified: false,
      joinDate: DateTime(2023, 5, 5),
      followersCount: 324,
      followingCount: 156,
      postsCount: 65,
      publicKey: 'jkl012publickey',
      privateKey: 'jkl012privatekey',
    ),
    MockUser(
      id: 'user5',
      username: 'mike_design',
      displayName: 'Mike',
      email: 'mike@example.com',
      profileImageUrl: 'https://randomuser.me/api/portraits/men/5.jpg',
      coverImageUrl: 'https://picsum.photos/800/200?random=5',
      bio: 'UI/UX Designer | Web3 explorer | Coffee addict',
      isVerified: true,
      joinDate: DateTime(2023, 3, 18),
      followersCount: 721,
      followingCount: 215,
      postsCount: 118,
      publicKey: 'mno345publickey',
      privateKey: 'mno345privatekey',
    ),
  ];

  // Posts
  static final List<MockPost> posts = [
    MockPost(
      id: 'post1',
      userId: 'user1',
      content: 'Just launched the alpha version of Deltanium! A blockchain-based social network where you own your content. #Blockchain #Web3 #Decentralized',
      mediaUrls: ['https://picsum.photos/600/400?random=10'],
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      likesCount: 42,
      commentsCount: 7,
      repostsCount: 12,
      comments: [
        MockComment(
          id: 'comment1',
          userId: 'user2',
          content: 'This is amazing! Can\'t wait to try it out.',
          createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 45)),
          likesCount: 5,
          repliesCount: 1,
        ),
        MockComment(
          id: 'comment2',
          userId: 'user3',
          content: 'Great job! The encryption features look promising.',
          createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 30)),
          likesCount: 3,
          repliesCount: 0,
        ),
      ],
    ),
    MockPost(
      id: 'post2',
      userId: 'user2',
      content: 'Just uploaded a new file to Deltanium blockchain. The encryption is seamless and I love that I can control who has access to my content.',
      mediaUrls: ['https://picsum.photos/600/400?random=11'],
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      likesCount: 23,
      commentsCount: 4,
      repostsCount: 2,
      comments: [
        MockComment(
          id: 'comment3',
          userId: 'user5',
          content: 'The UI is so clean! Great work on the design.',
          createdAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 50)),
          likesCount: 7,
          repliesCount: 2,
        ),
      ],
    ),
    MockPost(
      id: 'post3',
      userId: 'user3',
      content: 'Working on a new project using Deltanium as the backbone for user content management. The blockchain verification is impressive!',
      mediaUrls: [],
      createdAt: DateTime.now().subtract(const Duration(hours: 10)),
      likesCount: 18,
      commentsCount: 3,
      repostsCount: 1,
      comments: [],
    ),
    MockPost(
      id: 'post4',
      userId: 'user5',
      content: 'Designed a new interface for decentralized content sharing. What do you think? #Design #UI #UX #Web3',
      mediaUrls: [
        'https://picsum.photos/600/400?random=12',
        'https://picsum.photos/600/400?random=13',
      ],
      createdAt: DateTime.now().subtract(const Duration(hours: 8)),
      likesCount: 56,
      commentsCount: 8,
      repostsCount: 14,
      comments: [],
    ),
    MockPost(
      id: 'post5',
      userId: 'user4',
      content: 'Just discovered Deltanium and I\'m impressed by the technology behind it. The way it manages privacy while maintaining a social experience is groundbreaking.',
      mediaUrls: [],
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
      likesCount: 31,
      commentsCount: 6,
      repostsCount: 4,
      comments: [],
    ),
    MockPost(
      id: 'post6',
      userId: 'user1',
      content: 'Working on a new feature that will allow content creators to monetize their posts directly through the blockchain. No middlemen, no fees. #Crypto #ContentCreators',
      mediaUrls: ['https://picsum.photos/600/400?random=14'],
      createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
      likesCount: 78,
      commentsCount: 12,
      repostsCount: 21,
      comments: [],
    ),
    MockPost(
      id: 'post7',
      userId: 'user2',
      content: 'Gave a talk about Deltanium at the Web3 Summit yesterday. The response was overwhelming! So many developers interested in building on our protocol.',
      mediaUrls: [
        'https://picsum.photos/600/400?random=15',
        'https://picsum.photos/600/400?random=16',
        'https://picsum.photos/600/400?random=17',
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 18)),
      likesCount: 112,
      commentsCount: 24,
      repostsCount: 43,
      comments: [],
    ),
    MockPost(
      id: 'post8',
      userId: 'user3',
      content: 'The privacy-first approach of Deltanium makes it stand out from other social platforms. You can share content without worrying about your data being sold.',
      mediaUrls: [],
      createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 5)),
      likesCount: 29,
      commentsCount: 7,
      repostsCount: 8,
      comments: [],
    ),
  ];

  // Notifications
  static final List<MockNotification> notifications = [
    MockNotification(
      id: 'notif1',
      userId: 'user2',
      type: NotificationType.like,
      postId: 'post1',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      isRead: false,
    ),
    MockNotification(
      id: 'notif2',
      userId: 'user3',
      type: NotificationType.repost,
      postId: 'post1',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      isRead: false,
    ),
    MockNotification(
      id: 'notif3',
      userId: 'user4',
      type: NotificationType.follow,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      isRead: true,
    ),
    MockNotification(
      id: 'notif4',
      userId: 'user5',
      type: NotificationType.comment,
      postId: 'post1',
      commentId: 'comment1',
      createdAt: DateTime.now().subtract(const Duration(hours: 4)),
      isRead: true,
    ),
    MockNotification(
      id: 'notif5',
      userId: 'user2',
      type: NotificationType.mention,
      postId: 'post3',
      createdAt: DateTime.now().subtract(const Duration(hours: 6)),
      isRead: false,
    ),
  ];
} 
