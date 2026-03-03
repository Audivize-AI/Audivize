To run this program you need the following plist requirments:
GIDClientID = client id
Privacy - Camera Usage Description = (any string)
You may need to manually add to the Link Binary With Libraries:
  -GoogleSignIn
  -GoogleSignInSwift
When using the GoogleSignIn library you also may need to manually add a URL type
  -In URL scheme copy and paste the google sign in URL
