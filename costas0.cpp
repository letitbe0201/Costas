// This is a simple model of the costas loop design
// Debugs the parameters for the costas loop EE287 project
//
#include <stdio.h>
#include <iostream>
#include <fstream>
#include <math.h>
using namespace std;

double PI=3.14159265;
double TPI=2.0*PI;

double Carrier=2.000000e6;
double BitRate=5e5;
double SampleRate=2e7;
double SamplePeriod=1.0/SampleRate;
#define Samples 40000
double NCO=1024.0*0.0;
double Phase=1024.0/(SampleRate/(Carrier*1.01));

double Pcarrier = 1024.0/(SampleRate/(Carrier));

ofstream pcmd;

double sint[Samples];
double ccos[Samples];
double scos[Samples];
double fback[Samples];
double phist[Samples];
double fres[Samples];
double braw[Samples];
double nco[Samples];
double vsq[Samples];

// The Low pass filter is a compromise. (It is scaled to 1024 to help integer
// implementations later
#define ntaps 43
double filt[ntaps]={
2,
4,
4,
2,
-3,
-10,
-14,
-14,
-6,
7,
19,
22,
12,
-11,
-36,
-48,
-35,
11,
83,
161,
221,
244,
221,
161,
83,
11,
-35,
-48,
-36,
-11,
12,
22,
19,
7,
-6,
-14,
-14,
-10,
-3,
2,
4,
4,
2
};

#define T5(x) x,x,x,x,x,x,x,x,x,x,x,x,x,x,x,x,x,x,x,x,x,x,x,x,x 

// Sync pattern is 1010 1110 1011 0011 1001 for algorithm development only.
// Actual project uses a different sync pattern...
#define syncSize (20*25)
double syncCoef[syncSize]={
T5(1.0),T5(-1.0),T5(1.0),T5(-1.0),T5(1.0),T5(1.0),T5(1.0),T5(-1.0),
T5(1.0),T5(-1.0),T5(1.0),T5(1.0),T5(-1.0),T5(-1.0),T5(1.0),T5(1.0),
T5(1.0),T5(-1.0),T5(-1.0),T5(1.0)};


double filtcmem[ntaps];
double filtsmem[ntaps];
double modulation[Samples];
int filtoffset=0;

unsigned char data[Samples/(8*25)+1];

void fillSint(){
  int i;
  for(i=0; i < 2000/(8*25); i++) data[i]=0x00;
  data[2000/(8*25)]=0x75;
  data[2000/(8*25)+1]=0xcd;
  data[2000/(8*25)+2]=0x29;
  for(i=2000/(8*25)+3; i < Samples/(8*25)+1; i++) data[i]=i;
  unsigned wd=0;
  int wdx=0;
  for(i=0; i < Samples; i++) {
    if((i%(25*8))==0) {
      wd=data[wdx++];
    } else if( (i%25)==0) wd=wd >> 1;
    modulation[i]=((wd&1)!=0)?1.0:-1.0;
    sint[i]=sin(TPI*Carrier*i*SamplePeriod)*modulation[i];
  }
  for(i=0; i < ntaps; i++) {
    filtcmem[i]=0.0;
    filtsmem[i]=0.0;
  }

}


void dumpSint(double dat[],string fname)
{
  ofstream fout;
  pcmd << "TITLE=" << "\"" << fname << "\"" << endl;
  pcmd << "plot " << "\"" << fname << "\" with lines" << endl;
  fout.open(fname.data());
  int i;
  for(i=0; i < Samples; i++){
    fout << i << " " << dat[i] << endl;
  }
  fout.close();
  pcmd << "pause -1" << endl;
}
void dump2Sint(double dat[],string fname,double dat1[],string fname1)
{
  ofstream fout,fout1;
  pcmd << "TITLE=" << "\"" << fname << "\"" << endl;
  pcmd << "plot " << "\"" << fname << "\" with lines, \""<<fname1 << "\" with lines" << endl;
  fout.open(fname.data());
  fout1.open(fname1.data());
  int i;
  for(i=0; i < Samples; i++){
    fout << i << " " << dat[i] << endl;
    fout1 << i << " "<< dat1[i] << endl;
  }
  fout.close();
  fout1.close();
  pcmd << "pause -1" << endl;
}


void stepLoop(int ix)
{
  double ct,st;
  int ncoi=(int)NCO;
  st=sin(TPI*ncoi/1024.0);
  nco[ix]=st;
  ct=cos(TPI*ncoi/1024.0);
  ccos[ix]=ct*sint[ix];
  scos[ix]=-st*sint[ix];
  vsq[ix]=ccos[ix]*ccos[ix]+scos[ix]*scos[ix];
  filtcmem[filtoffset]=ccos[ix];
  filtsmem[filtoffset]=scos[ix];
  filtoffset = (filtoffset+1)%ntaps;
  double cf=0.0;
  double sf=0.0;
  for(int iw=0; iw < ntaps; iw++){
    cf += filtcmem[ (filtoffset+iw)%ntaps ]*filt[iw];
    sf += filtsmem[ (filtoffset+iw)%ntaps ]*filt[iw];
  }
  cf /= 1024.0;
  ccos[ix]=cf;
  sf /= 1024.0;
  scos[ix]=sf;
  double pfp= cf*sf;
  
  braw[ix]=pfp;
  Phase = Pcarrier+(pfp-0.00)*4.0;
  
  if(Phase < 0.0) Phase = 0.0;
  if(Phase > 1023.0) Phase = 1023.0;
  phist[ix]=Phase;
  NCO=NCO+Phase;
  if(NCO >=1024.0)NCO=NCO-1024.0;
  fres[ix]=SampleRate*Phase/1024.0;
}

void runLoop()
{
  int ix;
  for(ix=0; ix < Samples; ix++) stepLoop(ix);
}

double sync[Samples];
double maxsyncSeen=.7;
int maxloc=-1;
void calcSync()
{
   for(int i=0; i < Samples; i++) sync[i]=0.0;
   for(int i=syncSize/2; i< Samples-syncSize/2; i++){
     double ss=0.0;
     for(int j=-syncSize/2; j<syncSize/2; j++) ss += ccos[i+j]*syncCoef[j+syncSize/2];
     ss /= 250; // normalization only for plotting purposes
     sync[i-13]=ss;
     if(ss > maxsyncSeen || ss < -maxsyncSeen) {
       maxsyncSeen= (ss > 0.0)?ss:-ss;
       maxloc=i;
     }
   }
   cout << "Sync seen at " << maxloc << endl;
}


int main()
{
  cout << "Hi Morris" << endl;
  fillSint();
  pcmd.open("plot.txt");
  
  runLoop();
  calcSync();
//  dumpSint(modulation,"mod.txt");
  dump2Sint(ccos,"ccos.txt",sync,"sync.txt"); //,sint,"sint.txt");
//  dumpSint(sync,"sync.txt");
//  dumpSint(fback,"fback.txt");
//  dumpSint(fres,"freqs.txt");
  
  pcmd.close();
  return 0;
}
