/***************************************************************************
 *   Copyright (C) 2007-2010 by Sindre Aamås                               *
 *   aamas@stud.ntnu.no                                                    *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License version 2 as     *
 *   published by the Free Software Foundation.                            *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License version 2 for more details.                *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   version 2 along with this program; if not, write to the               *
 *   Free Software Foundation, Inc.,                                       *
 *   59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             *
 ***************************************************************************/
#ifndef MEMPTRS_H
#define MEMPTRS_H

namespace gambatte {

enum OamDmaSrc { OAM_DMA_SRC_ROM, OAM_DMA_SRC_SRAM, OAM_DMA_SRC_VRAM,
                 OAM_DMA_SRC_WRAM, OAM_DMA_SRC_INVALID, OAM_DMA_SRC_OFF };

class MemPtrs {
public:
	const unsigned char *rmem_[0x10];
	      unsigned char *wmem_[0x10];
	
	unsigned char *romdata_[2];
	unsigned char *wramdata_[2];
	unsigned char *vrambankptr_;
	unsigned char *rsrambankptr_;
	unsigned char *wsrambankptr_;
	unsigned char *memchunk_;
	unsigned char *rambankdata_;
	unsigned char *wramdataend_;
	
	OamDmaSrc oamDmaSrc_;
	
	MemPtrs(const MemPtrs &);
	MemPtrs & operator=(const MemPtrs &);
	void disconnectOamDmaAreas();
	unsigned char * rdisabledRamw();
	unsigned char * wdisabledRam();
	enum RamFlag { READ_EN = 1, WRITE_EN = 2, RTC_EN = 4 };
	
	MemPtrs();
	~MemPtrs();
	void reset(unsigned rombanks, unsigned rambanks, unsigned wrambanks);
	
	const unsigned char * rmem(unsigned area);
	unsigned char * wmem(unsigned area);
	unsigned char * vramdata();
	unsigned char * vramdataend();
	unsigned char * romdata();
	unsigned char * romdata(unsigned area);
	unsigned char * romdataend();
	unsigned char * wramdata(unsigned area);
	unsigned char * wramdataend();
	unsigned char * rambankdata();
	unsigned char * rambankdataend();
	const unsigned char * rdisabledRam();
	const unsigned char * rsrambankptr();
	unsigned char * wsrambankptr();
	unsigned char * vrambankptr();
	OamDmaSrc oamDmaSrc();
	
	void setRombank0(unsigned bank);
	void setRombank(unsigned bank);
	void setRambank(unsigned ramFlags, unsigned rambank);
	void setVrambank(unsigned bank);
	void setWrambank(unsigned bank);
	void setOamDmaSrc(OamDmaSrc oamDmaSrc);
};

}

#endif
