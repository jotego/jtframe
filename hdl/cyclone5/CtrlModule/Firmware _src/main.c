#include "host.h"

#include "minfat.h"
#include "spi.h"
#include <string.h>

fileTYPE file;

static int LoadROM(const char *filename)
{
	int result=0;
	int opened;
	HW_HOST(REG_HOST_CONTROL)=HOST_CONTROL_RESET |  HOST_CONTROL_DIVERT_SDCARD; // Hacer reset y tomar el control de la SD

	if((opened=FileOpen(&file,filename)))
	{
		int filesize=file.size;
		unsigned int c=0;
		int bits;

		bits=0;
		c=filesize-1;
		while(c)
		{
			++bits;
			c>>=1;
		}
		bits-=9;

		result=1;

		while(filesize>0)
		{
			//OSD_ProgressBar(c,bits);
			if(FileRead(&file,sector_buffer))
			{
				int i;
				int *p=(int *)&sector_buffer;
				for(i=0;i<512;i+=4)
				{
					unsigned int t=*p++;
					HW_HOST(REG_HOST_BOOTDATA)=t;
				}
			}
			else
			{
				result=0;
				filesize=512;
			}
			FileNextSector(&file);
			filesize-=512;
			++c;
		}
	}
	HW_HOST(REG_HOST_ROMSIZE) = file.size;
	HW_HOST(REG_HOST_CONTROL)=HOST_CONTROL_DIVERT_SDCARD; // Suelta el reset y mantenemos el control de la SD

	return(result);
}


int main(int argc,char **argv)
{
	int i;
	int dipsw=0;

	// Put the host core in reset while we initialise...
//	HW_HOST(REG_HOST_CONTROL)=HOST_CONTROL_RESET | HOST_CONTROL_DIVERT_SDCARD;

	//PS2Init();
	EnableInterrupts();

	HW_HOST(REG_HOST_CONTROL)=HOST_CONTROL_DIVERT_SDCARD; 
	// Release reset but take control of the SD card
	
	//OSD_Puts("Initializing SD card\n");

	if(!FindDrive())
		return(0);

//	OSD_Puts("Loading initial ROM...\n");

	LoadROM("SBAGMAN ROM");

//	FileSelector_SetLoadFunction(LoadROM);
	
	return(0);
}
