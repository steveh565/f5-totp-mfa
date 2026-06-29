// Minimal QR Code Generator - no external dependencies
// Based on ISO/IEC 18004 QR Code specification
var QRCode=(function(){
'use strict';
function QR(t,e){
  this.typeNumber=t;
  this.ecl=e;
  this.modules=null;
  this.moduleCount=0;
  this.dataCache=null;
  this.dataList=[];
}
QR.prototype={
  addData:function(d){
    this.dataList.push(new QR8(d));
    this.dataCache=null;
  },
  make:function(){
    if(this.typeNumber<1){
      var t=1;
      for(t=1;t<40;t++){
        var r=QRRSBlock.getRSBlocks(t,this.ecl);
        var b=new QRBitBuffer();
        var c=0;
        for(var i=0;i<r.length;i++) c+=r[i].dataCount;
        for(var i=0;i<this.dataList.length;i++){
          var d=this.dataList[i];
          b.put(d.mode,4);
          b.put(d.getLength(),QRUtil.getLengthInBits(d.mode,t));
          d.write(b);
        }
        if(b.getLengthInBits()<=c*8) break;
      }
      this.typeNumber=t;
    }
    this.makeImpl(false,this.getBestMaskPattern());
  },
  makeImpl:function(t,m){
    this.moduleCount=this.typeNumber*4+17;
    this.modules=new Array(this.moduleCount);
    for(var r=0;r<this.moduleCount;r++){
      this.modules[r]=new Array(this.moduleCount);
      for(var c=0;c<this.moduleCount;c++)
        this.modules[r][c]=null;
    }
    this.setupPositionProbePattern(0,0);
    this.setupPositionProbePattern(this.moduleCount-7,0);
    this.setupPositionProbePattern(0,this.moduleCount-7);
    this.setupPositionAdjustPattern();
    this.setupTimingPattern();
    this.setupTypeInfo(t,m);
    if(this.typeNumber>=7) this.setupTypeNumber(t);
    if(this.dataCache==null)
      this.dataCache=QR.createData(this.typeNumber,this.ecl,this.dataList);
    this.mapData(this.dataCache,m);
  },
  setupPositionProbePattern:function(r,c){
    for(var dr=-1;dr<=7;dr++){
      if(r+dr<=-1||this.moduleCount<=r+dr) continue;
      for(var dc=-1;dc<=7;dc++){
        if(c+dc<=-1||this.moduleCount<=c+dc) continue;
        if((0<=dr&&dr<=6&&(dc==0||dc==6))||
           (0<=dc&&dc<=6&&(dr==0||dr==6))||
           (2<=dr&&dr<=4&&2<=dc&&dc<=4))
          this.modules[r+dr][c+dc]=true;
        else
          this.modules[r+dr][c+dc]=false;
      }
    }
  },
  getBestMaskPattern:function(){
    var min=0,pat=0;
    for(var i=0;i<8;i++){
      this.makeImpl(true,i);
      var lp=QRUtil.getLostPoint(this);
      if(i==0||min>lp){min=lp;pat=i;}
    }
    return pat;
  },
  setupTimingPattern:function(){
    for(var r=8;r<this.moduleCount-8;r++){
      if(this.modules[r][6]!=null) continue;
      this.modules[r][6]=(r%2==0);
    }
    for(var c=8;c<this.moduleCount-8;c++){
      if(this.modules[6][c]!=null) continue;
      this.modules[6][c]=(c%2==0);
    }
  },
  setupPositionAdjustPattern:function(){
    var p=QRUtil.getPatternPosition(this.typeNumber);
    for(var i=0;i<p.length;i++){
      for(var j=0;j<p.length;j++){
        var r=p[i],c=p[j];
        if(this.modules[r][c]!=null) continue;
        for(var dr=-2;dr<=2;dr++){
          for(var dc=-2;dc<=2;dc++){
            if(dr==-2||dr==2||dc==-2||dc==2||(dr==0&&dc==0))
              this.modules[r+dr][c+dc]=true;
            else
              this.modules[r+dr][c+dc]=false;
          }
        }
      }
    }
  },
  setupTypeNumber:function(t){
    var b=QRUtil.getBCHTypeNumber(this.typeNumber);
    for(var i=0;i<18;i++){
      var m=(!t&&((b>>i)&1)==1);
      this.modules[Math.floor(i/3)][i%3+this.moduleCount-8-3]=m;
    }
    for(var i=0;i<18;i++){
      var m=(!t&&((b>>i)&1)==1);
      this.modules[i%3+this.moduleCount-8-3][Math.floor(i/3)]=m;
    }
  },
  setupTypeInfo:function(t,mp){
    var d=(this.ecl<<3)|mp;
    var b=QRUtil.getBCHTypeInfo(d);
    for(var i=0;i<15;i++){
      var m=(!t&&((b>>i)&1)==1);
      if(i<6) this.modules[i][8]=m;
      else if(i<8) this.modules[i+1][8]=m;
      else this.modules[this.moduleCount-15+i][8]=m;
    }
    for(var i=0;i<15;i++){
      var m=(!t&&((b>>i)&1)==1);
      if(i<8) this.modules[8][this.moduleCount-i-1]=m;
      else if(i<9) this.modules[8][15-i-1+1]=m;
      else this.modules[8][15-i-1]=m;
    }
    this.modules[this.moduleCount-8][8]=(!t);
  },
  mapData:function(data,mp){
    var inc=-1,row=this.moduleCount-1,bIdx=7,byIdx=0;
    for(var col=this.moduleCount-1;col>0;col-=2){
      if(col==6) col--;
      while(true){
        for(var c=0;c<2;c++){
          if(this.modules[row][col-c]==null){
            var dk=false;
            if(byIdx<data.length)
              dk=(((data[byIdx]>>>bIdx)&1)==1);
            if(QRUtil.getMask(mp,row,col-c)) dk=!dk;
            this.modules[row][col-c]=dk;
            bIdx--;
            if(bIdx==-1){byIdx++;bIdx=7;}
          }
        }
        row+=inc;
        if(row<0||this.moduleCount<=row){
          row-=inc;inc=-inc;break;
        }
      }
    }
  }
};

QR.createData=function(tn,ecl,dl){
  var rs=QRRSBlock.getRSBlocks(tn,ecl);
  var buf=new QRBitBuffer();
  var tc=0;
  for(var i=0;i<rs.length;i++) tc+=rs[i].dataCount;
  for(var i=0;i<dl.length;i++){
    var d=dl[i];
    buf.put(d.mode,4);
    buf.put(d.getLength(),QRUtil.getLengthInBits(d.mode,tn));
    d.write(buf);
  }
  if(buf.getLengthInBits()+4<=tc*8) buf.put(0,4);
  while(buf.getLengthInBits()%8!=0) buf.putBit(false);
  while(true){
    if(buf.getLengthInBits()>=tc*8) break;
    buf.put(0xEC,8);
    if(buf.getLengthInBits()>=tc*8) break;
    buf.put(0x11,8);
  }
  return QR.createBytes(buf,rs);
};

QR.createBytes=function(buf,rs){
  var off=0,maxDc=0,maxEc=0;
  var dcd=new Array(rs.length);
  var ecd=new Array(rs.length);
  for(var r=0;r<rs.length;r++){
    var dc=rs[r].dataCount;
    var ec=rs[r].totalCount-dc;
    maxDc=Math.max(maxDc,dc);
    maxEc=Math.max(maxEc,ec);
    dcd[r]=new Array(dc);
    for(var i=0;i<dc;i++) dcd[r][i]=0xff&buf.buffer[i+off];
    off+=dc;
    var rp=QRUtil.getErrorCorrectPolynomial(ec);
    var rw=new QRPolynomial(dcd[r],rp.getLength()-1);
    var mp=rw.mod(rp);
    ecd[r]=new Array(rp.getLength()-1);
    for(var i=0;i<ecd[r].length;i++){
      var mi=i+mp.getLength()-ecd[r].length;
      ecd[r][i]=(mi>=0)?mp.get(mi):0;
    }
  }
  var tot=0;
  for(var i=0;i<rs.length;i++) tot+=rs[i].totalCount;
  var data=new Array(tot),idx=0;
  for(var i=0;i<maxDc;i++)
    for(var r=0;r<rs.length;r++)
      if(i<dcd[r].length) data[idx++]=dcd[r][i];
  for(var i=0;i<maxEc;i++)
    for(var r=0;r<rs.length;r++)
      if(i<ecd[r].length) data[idx++]=ecd[r][i];
  return data;
};

function QR8(d){this.mode=4;this.data=d;}
QR8.prototype={
  getLength:function(){return this.data.length;},
  write:function(b){
    for(var i=0;i<this.data.length;i++)
      b.put(this.data.charCodeAt(i),8);
  }
};

var QRUtil={
  PATTERN_POSITION_TABLE:[
    [],[6,18],[6,22],[6,26],[6,30],[6,34],
    [6,22,38],[6,24,42],[6,26,46],[6,28,50],[6,30,54],[6,32,58],[6,34,62],
    [6,26,46,66],[6,26,48,70],[6,26,50,74],[6,30,54,78],[6,30,56,82],
    [6,30,58,86],[6,34,62,90],[6,28,50,72,94],[6,26,50,74,98],
    [6,30,54,78,102],[6,28,54,80,106],[6,32,58,84,110],[6,30,58,86,114],
    [6,34,62,90,118],[6,26,50,74,98,122],[6,30,54,78,102,126],
    [6,26,52,78,104,130],[6,30,56,82,108,134],[6,34,60,86,112,138],
    [6,30,58,86,114,142],[6,34,62,90,118,146],[6,30,54,78,102,126,150],
    [6,24,50,76,102,128,154],[6,28,54,80,106,132,158],
    [6,32,58,84,110,136,162],[6,26,54,82,110,138,166],
    [6,30,58,86,114,142,170]
  ],
  G15:(1<<10)|(1<<8)|(1<<5)|(1<<4)|(1<<2)|(1<<1)|(1<<0),
  G18:(1<<12)|(1<<11)|(1<<10)|(1<<9)|(1<<8)|(1<<5)|(1<<2)|(1<<0),
  G15_MASK:(1<<14)|(1<<12)|(1<<10)|(1<<4)|(1<<1),
  getBCHTypeInfo:function(d){
    var e=d<<10;
    while(QRUtil.getBCHDigit(e)-QRUtil.getBCHDigit(QRUtil.G15)>=0)
      e^=(QRUtil.G15<<(QRUtil.getBCHDigit(e)-QRUtil.getBCHDigit(QRUtil.G15)));
    return((d<<10)|e)^QRUtil.G15_MASK;
  },
  getBCHTypeNumber:function(d){
    var e=d<<12;
    while(QRUtil.getBCHDigit(e)-QRUtil.getBCHDigit(QRUtil.G18)>=0)
      e^=(QRUtil.G18<<(QRUtil.getBCHDigit(e)-QRUtil.getBCHDigit(QRUtil.G18)));
    return(d<<12)|e;
  },
  getBCHDigit:function(d){
    var n=0;
    while(d!=0){n++;d>>>=1;}
    return n;
  },
  getPatternPosition:function(t){
    return QRUtil.PATTERN_POSITION_TABLE[t-1];
  },
  getMask:function(m,i,j){
    switch(m){
      case 0:return(i+j)%2==0;
      case 1:return i%2==0;
      case 2:return j%3==0;
      case 3:return(i+j)%3==0;
      case 4:return(Math.floor(i/2)+Math.floor(j/3))%2==0;
      case 5:return(i*j)%2+(i*j)%3==0;
      case 6:return((i*j)%2+(i*j)%3)%2==0;
      case 7:return((i*j)%3+(i+j)%2)%2==0;
      default:throw new Error('bad mask');
    }
  },
  getErrorCorrectPolynomial:function(l){
    var a=new QRPolynomial([1],0);
    for(var i=0;i<l;i++)
      a=a.multiply(new QRPolynomial([1,QRMath.gexp(i)],0));
    return a;
  },
  getLengthInBits:function(m,t){
    if(t<10){
      switch(m){case 1:return 10;case 2:return 9;case 4:return 8;case 8:return 8;}
    }else if(t<27){
      switch(m){case 1:return 12;case 2:return 11;case 4:return 16;case 8:return 10;}
    }else{
      switch(m){case 1:return 14;case 2:return 13;case 4:return 16;case 8:return 12;}
    }
    throw new Error('mode:'+m);
  },
  getLostPoint:function(q){
    var mc=q.moduleCount,lp=0;
    for(var r=0;r<mc;r++){
      for(var c=0;c<mc;c++){
        var s=0,d=q.modules[r][c];
        for(var dr=-1;dr<=1;dr++){
          if(r+dr<0||mc<=r+dr) continue;
          for(var dc=-1;dc<=1;dc++){
            if(c+dc<0||mc<=c+dc) continue;
            if(dr==0&&dc==0) continue;
            if(d==q.modules[r+dr][c+dc]) s++;
          }
        }
        if(s>5) lp+=(3+s-5);
      }
    }
    for(var r=0;r<mc-1;r++){
      for(var c=0;c<mc-1;c++){
        var n=0;
        if(q.modules[r][c]) n++;
        if(q.modules[r+1][c]) n++;
        if(q.modules[r][c+1]) n++;
        if(q.modules[r+1][c+1]) n++;
        if(n==0||n==4) lp+=3;
      }
    }
    for(var r=0;r<mc;r++)
      for(var c=0;c<mc-6;c++)
        if(q.modules[r][c]&&!q.modules[r][c+1]&&q.modules[r][c+2]&&
           q.modules[r][c+3]&&q.modules[r][c+4]&&!q.modules[r][c+5]&&
           q.modules[r][c+6]) lp+=40;
    for(var c=0;c<mc;c++)
      for(var r=0;r<mc-6;r++)
        if(q.modules[r][c]&&!q.modules[r+1][c]&&q.modules[r+2][c]&&
           q.modules[r+3][c]&&q.modules[r+4][c]&&!q.modules[r+5][c]&&
           q.modules[r+6][c]) lp+=40;
    var dn=0;
    for(var c=0;c<mc;c++)
      for(var r=0;r<mc;r++)
        if(q.modules[r][c]) dn++;
    lp+=Math.abs(100*dn/mc/mc-50)/5*10;
    return lp;
  }
};

var QRMath={
  glog:function(n){
    if(n<1) throw new Error('glog');
    return QRMath.LOG_TABLE[n];
  },
  gexp:function(n){
    while(n<0) n+=255;
    while(n>=256) n-=255;
    return QRMath.EXP_TABLE[n];
  },
  EXP_TABLE:new Array(256),
  LOG_TABLE:new Array(256)
};
for(var i=0;i<8;i++) QRMath.EXP_TABLE[i]=1<<i;
for(var i=8;i<256;i++)
  QRMath.EXP_TABLE[i]=QRMath.EXP_TABLE[i-4]^QRMath.EXP_TABLE[i-5]^
                       QRMath.EXP_TABLE[i-6]^QRMath.EXP_TABLE[i-8];
for(var i=0;i<255;i++) QRMath.LOG_TABLE[QRMath.EXP_TABLE[i]]=i;

function QRPolynomial(n,s){
  if(n.length==undefined) throw new Error(n.length+'/'+s);
  var o=0;
  while(o<n.length&&n[o]==0) o++;
  this.num=new Array(n.length-o+s);
  for(var i=0;i<n.length-o;i++) this.num[i]=n[i+o];
}
QRPolynomial.prototype={
  get:function(i){return this.num[i];},
  getLength:function(){return this.num.length;},
  multiply:function(e){
    var n=new Array(this.getLength()+e.getLength()-1);
    for(var i=0;i<this.getLength();i++)
      for(var j=0;j<e.getLength();j++)
        n[i+j]^=QRMath.gexp(QRMath.glog(this.get(i))+QRMath.glog(e.get(j)));
    return new QRPolynomial(n,0);
  },
  mod:function(e){
    if(this.getLength()-e.getLength()<0) return this;
    var r=QRMath.glog(this.get(0))-QRMath.glog(e.get(0));
    var n=new Array(this.getLength());
    for(var i=0;i<this.getLength();i++) n[i]=this.get(i);
    for(var i=0;i<e.getLength();i++)
      n[i]^=QRMath.gexp(QRMath.glog(e.get(i))+r);
    return new QRPolynomial(n,0).mod(e);
  }
};

var QRRSBlock={
  RS_BLOCK_TABLE:[
    [1,26,19],[1,26,16],[1,26,13],[1,26,9],
    [1,44,34],[1,44,28],[1,44,22],[1,44,16],
    [1,70,55],[1,70,44],[2,35,17],[2,35,13],
    [1,100,80],[2,50,32],[2,50,24],[4,25,9],
    [1,134,108],[2,67,43],[2,33,15,2,34,16],[2,33,11,2,34,12],
    [2,86,68],[4,43,27],[4,43,19],[4,43,15],
    [2,98,78],[4,49,31],[2,32,14,4,33,15],[4,39,13,1,40,14],
    [2,121,97],[2,60,38,2,61,39],[4,40,18,2,41,19],[4,40,14,2,41,15],
    [2,146,116],[3,58,36,2,59,37],[4,36,16,4,37,17],[4,36,12,4,37,13],
    [2,86,68,2,87,69],[4,69,43,1,70,44],[6,43,19,2,44,20],[6,43,15,2,44,16],
    [4,101,81],[1,80,50,4,81,51],[4,50,22,4,51,23],[3,36,12,8,37,13],
    [2,116,92,2,117,93],[6,58,36,2,59,37],[4,46,20,6,47,21],[7,42,14,4,43,15],
    [4,133,107],[8,59,37,1,60,38],[8,44,20,4,45,21],[12,33,11,4,34,12],
    [3,145,115,1,146,116],[4,64,40,5,65,41],[11,36,16,5,37,17],[11,36,12,5,37,13],
    [5,109,87,1,110,88],[5,65,41,5,66,42],[5,54,24,7,55,25],[11,36,12,7,37,13],
    [5,122,98,1,123,99],[7,73,45,3,74,46],[15,43,19,2,44,20],[3,45,15,13,46,16],
    [1,135,107,5,136,108],[10,74,46,1,75,47],[1,50,22,15,51,23],[2,42,14,17,43,15],
    [5,150,120,1,151,121],[9,69,43,4,70,44],[17,50,22,1,51,23],[2,42,14,19,43,15],
    [3,141,113,4,142,114],[3,70,44,11,71,45],[17,47,21,4,48,22],[9,39,13,16,40,14],
    [3,135,107,5,136,108],[3,67,41,13,68,42],[15,54,24,5,55,25],[15,43,15,10,44,16],
    [4,144,116,4,145,117],[17,68,42],[17,50,22,6,51,23],[19,46,16,6,47,17],
    [2,139,111,7,140,112],[17,74,46],[7,54,24,16,55,25],[34,37,13],
    [4,151,121,5,152,122],[4,75,47,14,76,48],[11,54,24,14,55,25],[16,45,15,14,46,16],
    [6,147,117,4,148,118],[6,73,45,14,74,46],[11,54,24,16,55,25],[30,46,16,2,47,17],
    [8,132,106,4,133,107],[8,75,47,13,76,48],[7,54,24,22,55,25],[22,45,15,13,46,16],
    [10,142,114,2,143,115],[19,74,46,4,75,47],[28,50,22,6,51,23],[33,46,16,4,47,17],
    [8,152,122,4,153,123],[22,73,45,3,74,46],[8,53,23,26,54,24],[12,45,15,28,46,16],
    [3,147,117,10,148,118],[3,73,45,23,74,46],[4,54,24,31,55,25],[11,45,15,31,46,16],
    [7,146,116,7,147,117],[21,73,45,7,74,46],[1,53,23,37,54,24],[19,45,15,26,46,16],
    [5,145,115,10,146,116],[19,75,47,10,76,48],[15,54,24,25,55,25],[23,45,15,25,46,16],
    [13,145,115,3,146,116],[2,74,46,29,75,47],[42,54,24,1,55,25],[23,45,15,28,46,16],
    [17,145,115],[10,74,46,23,75,47],[10,54,24,35,55,25],[19,45,15,35,46,16],
    [17,145,115,1,146,116],[14,74,46,21,75,47],[29,54,24,19,55,25],[11,45,15,46,46,16],
    [13,145,115,6,146,116],[14,74,46,23,75,47],[44,54,24,7,55,25],[59,46,16,1,47,17],
    [12,151,121,7,152,122],[12,75,47,26,76,48],[39,54,24,14,55,25],[22,45,15,41,46,16],
    [6,151,121,14,152,122],[6,75,47,34,76,48],[46,54,24,10,55,25],[2,45,15,64,46,16],
    [17,152,122,4,153,123],[29,74,46,14,75,47],[49,54,24,10,55,25],[24,45,15,46,46,16],
    [4,152,122,18,153,123],[13,74,46,32,75,47],[48,54,24,14,55,25],[42,45,15,32,46,16],
    [20,147,117,4,148,118],[40,75,47,7,76,48],[43,54,24,22,55,25],[10,45,15,67,46,16],
    [19,148,118,6,149,119],[18,75,47,31,76,48],[34,54,24,34,55,25],[20,45,15,61,46,16]
  ],
  getRSBlocks:function(t,e){
    var r=QRRSBlock.getRsBlockTable(t,e);
    if(r==undefined) throw new Error('bad rs block');
    var l=r.length/3,list=[];
    for(var i=0;i<l;i++){
      var c=r[i*3+0],tc=r[i*3+1],dc=r[i*3+2];
      for(var j=0;j<c;j++) list.push({totalCount:tc,dataCount:dc});
    }
    return list;
  },
  getRsBlockTable:function(t,e){
    switch(e){
      case 1:return QRRSBlock.RS_BLOCK_TABLE[(t-1)*4+0];
      case 0:return QRRSBlock.RS_BLOCK_TABLE[(t-1)*4+1];
      case 3:return QRRSBlock.RS_BLOCK_TABLE[(t-1)*4+2];
      case 2:return QRRSBlock.RS_BLOCK_TABLE[(t-1)*4+3];
      default:return undefined;
    }
  }
};

function QRBitBuffer(){this.buffer=[];this.length=0;}
QRBitBuffer.prototype={
  get:function(i){
    return((this.buffer[Math.floor(i/8)]>>>(7-i%8))&1)==1;
  },
  put:function(n,l){
    for(var i=0;i<l;i++) this.putBit(((n>>>(l-i-1))&1)==1);
  },
  getLengthInBits:function(){return this.length;},
  putBit:function(b){
    var bi=Math.floor(this.length/8);
    if(this.buffer.length<=bi) this.buffer.push(0);
    if(b) this.buffer[bi]|=(0x80>>>(this.length%8));
    this.length++;
  }
};

return QR;
})();

// Render QR code to a canvas element
function renderQR(canvasId, text, scale) {
    scale = scale || 6;
    var qr = new QRCode(0, 1); // auto type, L error correction
    qr.addData(text);
    qr.make();
    var cv = document.getElementById(canvasId);
    var cx = cv.getContext('2d');
    var sz = qr.moduleCount;
    cv.width = sz * scale;
    cv.height = sz * scale;
    cx.fillStyle = '#ffffff';
    cx.fillRect(0, 0, cv.width, cv.height);
    cx.fillStyle = '#000000';
    for (var r = 0; r < sz; r++)
        for (var c = 0; c < sz; c++)
            if (qr.modules[r][c])
                cx.fillRect(c * scale, r * scale, scale, scale);
}