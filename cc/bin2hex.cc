#include <iostream>
#include <iomanip>

using namespace std;

int main() {
    while( true ) {
        unsigned char b[1024];
        cin.read( (char*) b,1024);
        for( int k=0; k<1024; k+=2 ) {
            unsigned c = b[k];
            unsigned d = b[k+1];
            c = (c<<8)|d;
            cout << hex << c <<'\n';
        }
        if(cin.eof()) break;
    }
    return 0;
}