#include <windows.h>
#include <stdio.h>
#include <string.h>
static int test_file_io(void) {
    WCHAR dir[MAX_PATH], path[MAX_PATH];
    HANDLE file; DWORD n; char data[32]={0};
    if (!GetTempPathW(MAX_PATH,dir) || !GetTempFileNameW(dir,L"cpr",0,path)) return 10;
    file=CreateFileW(path,GENERIC_READ|GENERIC_WRITE,0,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
    if (file==INVALID_HANDLE_VALUE) return 11;
    if (!WriteFile(file,"cyder-pr3",9,&n,NULL) || n!=9) return 12;
    if (SetFilePointer(file,0,NULL,FILE_BEGIN)==INVALID_SET_FILE_POINTER) return 13;
    if (!ReadFile(file,data,9,&n,NULL) || n!=9 || memcmp(data,"cyder-pr3",9)) return 14;
    if (!CloseHandle(file) || !DeleteFileW(path)) return 15;
    SetLastError(0);
    file=CreateFileW(path,GENERIC_READ,0,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
    if (file!=INVALID_HANDLE_VALUE || GetLastError()!=ERROR_FILE_NOT_FOUND) return 16;
    puts("PASS native Win32 file round-trip and missing-file error");
    return 0;
}

#include <windows.h>
#include <bcrypt.h>
#include <stdio.h>
static int test_bcrypt(void) {
    BCRYPT_ALG_HANDLE alg=NULL; BCRYPT_KEY_HANDLE key=NULL, public_key=NULL;
    UCHAR hash[32]={0x42}, sig[128], public_blob[256]; ULONG n=0, public_size=0; NTSTATUS st;
    st=BCryptOpenAlgorithmProvider(&alg,BCRYPT_ECDSA_P256_ALGORITHM,NULL,0); if(st) return 20;
    st=BCryptGenerateKeyPair(alg,&key,256,0); if(st) return 21;
    st=BCryptFinalizeKeyPair(key,0); if(st) return 22;
    st=BCryptSignHash(key,NULL,hash,sizeof(hash),sig,sizeof(sig),&n,0); if(st || !n) return 23;
    st=BCryptExportKey(key,NULL,BCRYPT_ECCPUBLIC_BLOB,public_blob,sizeof(public_blob),&public_size,0); if(st) return 26;
    st=BCryptImportKeyPair(alg,NULL,BCRYPT_ECCPUBLIC_BLOB,&public_key,public_blob,public_size,0); if(st) return 27;
    st=BCryptVerifySignature(public_key,NULL,hash,sizeof(hash),sig,n,0); if(st) return 24;
    sig[0]^=1;
    st=BCryptVerifySignature(public_key,NULL,hash,sizeof(hash),sig,n,0); if(!st) return 25;
    BCryptDestroyKey(public_key); BCryptDestroyKey(key); BCryptCloseAlgorithmProvider(alg,0);
    puts("PASS BCrypt P-256 imported public key: valid signature accepted; modified signature rejected");
    return 0;
}

int main(void)
{
    int result = test_file_io();
    if (!result) result = test_bcrypt();
    if (result) fprintf(stderr, "runtime smoke failed at stage %d\n", result);
    return result;
}
