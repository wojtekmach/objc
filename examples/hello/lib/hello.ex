defmodule Hello do
  use ObjC, compile: "-lobjc -framework AVFoundation"

  defobjc(:hello, 0, ~S"""
  // #ifdef DARWIN
  #import "AVFoundation/AVFoundation.h"

  void request_permission() {
      if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized) {
          printf("mic authorized\n");
      }
      else {
          printf("mic not authorized\n");
      }

      [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
          if (granted) {
              printf("mic granted\n");
          }
          else {
              printf("mic not granted\n");
          }
      }];
  }
  // #else
  // void request_permission() {}
  // #endif

  static ERL_NIF_TERM hello(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
  {
      request_permission();
      return enif_make_string(env, "Hello world!", ERL_NIF_LATIN1);
  }
  """)
end
