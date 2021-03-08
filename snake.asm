        PROCESSOR 6502
        include "lib/vcs.h"
        include "lib/macro.h"


;---------------------------------------------------
;
;               General Documentation                  
;
;---------------------------------------------------


        ; Playfield "coordinates" (10 x 8)
        ;
        ;       1  2  3  4  5  6  7  8
        ;       |  |  |  |  |  |  |  |
        ;  1 -- 00 01 02 03 04 05 06 07
        ;  2 -- 08 09 0a 0b 0c 0d 0e 0f
        ;  3 -- 10 11 12 13 14 15 16 17
        ;  4 -- 18 19 1a 1b 1c 2d 2e 2f
        ;  5 -- 20 21 22 23 24 25 26 27 -- middle
        ;  6 -- 28 29 2a 2b 2c 2d 2e 2f -- middle
        ;  7 -- 30 31 32 33 34 35 36 37
        ;  8 -- 38 39 3a 3b 3c 3d 3e 3f
        ;  9 -- 40 41 42 43 44 45 46 47
        ; 10 -- 48 49 4a 4b 4c 4d 4e 4f
        ;                |  |
        ;                |  middle
        ;                middle


;---------------------------------------------------
;
;                     Constants                        
;
;---------------------------------------------------


SNAKECOLORNORMAL = #$c4
SNAKECOLORSLOW = #$94
SNAKECOLORFAST = #$42

SPEEDSLOW = #22
SPEEDNORMAL = #16
SPEEDFAST = #11

SIZEOFMAP = #$50


;---------------------------------------------------
;
;             RAM Variable Declarations                
;
;---------------------------------------------------


        ; variables here do not end up in ROM
        SEG.U VARS
        ORG $80 ; RAM starts at $80

ROWS ds 10 ; each byte = a row, bits 0-7 = columns 1 through 8
RANDOM ds 1 ; random number taken from RIOT chip timer
SNAKELENGTH ds 1 ; length of snake
SCORE ds 1 ; score: number of apples collected

        ; playfield location is determined by wrapping from
        ; left to right, up to down: #$00 (0 dec) to #$4f (79 dec)
SNAKEHEADLOCATION ds 1 ; where in the 10 x 8 playfield the snake's head is located

SNAKEOLDTAILPOINTER ds 1 ; where int the 10 x 8 playfield the snake's head is located
APPLELOCATION ds 1 ; where in the 10 x 8 playfield the apple is located
HEADDIRECTION ds 1 ; direction we want the snake to move in next turn
STOREDDIRECTION ds 1 ; direction that was last used
        
        ; points to where the head currently is in memory
HEADHISTORYPOINTER ds 1 ; pointer for where in the HEADHISTORY the current head is in
GAMEMODE ds 1 ; 0 = game playing, 1 = game over, 2 = game selection
LOOPROW ds 1 ; used to help draw the 10 rows in the playfield
ROWNUMBER ds 1 ; used in gamefield positioning calculation
COLUMNMASK ds 1 ; used in gamefield positioning calculation
COLUMNMASKINVERTED ds 1 ; inverted version of the COLUMNMASK
RENDERCOUNTER ds 1 ; a counter for determining if snake collision logic should be executed in the current frame
SELECTEDGAMETYPE ds 1 ; 0 = normal, 1 = slow, 2 = fast
DEBOUNCE ds 1 ; 0 = can select another option, 1 = user needs to release select lever
LEFTDIGITOFFSET ds 1 ; the scanline offset for the left digit of the score
RIGHTDIGITOFFSET ds 1 ; the scanline offset for the right digit of the score
LEVELOFFSET ds 1 ; the scanline offset for the selection menu level "L" character
SELECTEDGAMETYPEOFFSET ds 1 ; the scanline offset for the selection menu level (0, 1, 2) number
HEADERITERATIONSTORE ds 1 ; a helper storage variable for header rendering
RENDERSPEED ds 1 ; how fast the "game speed" is
SOUNDITERATOR ds 1 ; a variable containing the number of frames left for the sound to play

        ORG $a8 ; last 80 spots in ram, tracking snake head history
HEADHISTORY ds 80 ; a "history" of where the snake head has been in the 10 x 8 playfield


;---------------------------------------------------
;
;                     ROM Code                      
;
;---------------------------------------------------


        SEG CODE
        ORG $F800 ; 2k ROM


;---------------------------------------------------
;
;       Initialize Console and Ram Variables             
;
;---------------------------------------------------


InitSystem:
        ; set RAM, TIA registers and CPU registers to 0
        CLEAN_START

        ; seed the random number generator
        lda INTIM ; random value
        sta RANDOM ; use as seed

        ; init rows of the 10 x 8 playfield
        ldx #10; 10 rows
initrows:
        dex
        lda #%11111111 ; bits 0-7 all enabled
        sta ROWS,x
        cpx #0
        bne initrows

        ; add player 1 support
        lda #%11110000
        sta SWCHA

        ; init score
        lda #0
        sta SCORE

        ; setting render counter to 0
        lda #0
        sta RENDERCOUNTER

        ; setting game mode to difficulty selection
        lda #2
        sta GAMEMODE

        ; setting default game type (normal mode/green)
        lda #0
        sta SELECTEDGAMETYPE

        lda #5
        sta SELECTEDGAMETYPEOFFSET

        ; setting sound iterator to "not playing sound"
        lda #0
        sta SOUNDITERATOR

        ; clearing registers
        lda #0
        ldx #0
        ldy #0


;---------------------------------------------------
;
;                     Game Loop                       
;
;---------------------------------------------------


Main:
        jsr VerticalSync
        jsr VerticalBlank
        jsr Kernel
        jsr OverScan
        jmp Main

VerticalSync:
        lda #2
        ldx #49     
        sta WSYNC
        sta VSYNC
        stx TIM64T  ; set timer to go off in 41 scanlines (49 * 64) / 76
        sta WSYNC   ; Wait for Sync - halts CPU until end of 1st scanline of VSYNC
        sta WSYNC
        lda #0
        sta WSYNC
        sta VSYNC
        rts
    
    
        ; game logic can resides here
VerticalBlank:
        ; reseting loop row
        lda #0
        sta LOOPROW

        ; reseting render offset for 
        lda #0
        sta LEVELOFFSET

        ; checking if game is over
        lda GAMEMODE
        cmp #1
        beq lostgame

        ; checking is game mode is in "level selection" mode
        cmp #2
        beq choosegamemode

        jsr SetDirection ; poll user input
        jsr GenerateRandom ; generate random number
        
        ; checking if collision should be checked this frame or not
        lda RENDERCOUNTER
        cmp RENDERSPEED
        bne dontrender
        
        jsr GenerateRandom ; generate random number
        jsr CheckCollision

        ; reseting render counter after collision is checked for this frame
        lda #0
        sta RENDERCOUNTER
        jmp lostgame
dontrender:
        inc RENDERCOUNTER ; increment render counter until it meets the RENDERSPEED threshold
choosegamemode:
        jsr ProcessSwitches
lostgame:
        rts


Kernel:
        sta WSYNC
        lda INTIM ; check the timer
        bne Kernel ; branch if timer is not equal to 0
        ; turn on the display
        sta VBLANK ; Accumulator D1=0, turns off Vertical Blank signal (image output on)

        ; draw the screen
        ; 192 scanlines for the game (NTSC)
KernelLoop:

        ; set background color
        lda #0
        sta COLUBK

        ; set playfield color
        lda #$0a
        sta COLUPF

        ; checking is game mode is in "level selection" mode
        lda #2
        cmp GAMEMODE
        bne top20init

        ; iterates 20 times, a header for the screen containing the level selected
        ; this block of code is executed if the gamemode is 2
        ldx #20 ; 20 iterations
        ldy #0
top20title:

        lda #0
        sta PF2

        sta WSYNC

        lda #0
        sta PF0

        sty HEADERITERATIONSTORE

        ldy LEVELOFFSET
        lda levelletter,y
        sta PF2
        
        ldy SELECTEDGAMETYPEOFFSET
        lda digits,y
        sta PF0

        ldy HEADERITERATIONSTORE

        iny
        cpy #4
        bne continuetop20title
        inc LEVELOFFSET
        inc SELECTEDGAMETYPEOFFSET
        ldy #0
continuetop20title:
        dex
        bne top20title

        jmp clearPF

        ; iterates 20 times, a header for the screen containing the score
        ; this block of code is executed if the gamemode is either 0 or 1
top20init:
        ldx #20 ; 20 iterations
        ldy #0
top20:
        lda #0
        sta PF2

        sta WSYNC

        lda #0
        sta PF0

        sty HEADERITERATIONSTORE

        ; left digit
        ldy LEFTDIGITOFFSET
        lda digits,y
        sta PF2

        ; right digit
        ldy RIGHTDIGITOFFSET
        lda digits,y
        sta PF0

        ldy HEADERITERATIONSTORE

        iny
        cpy #4
        bne continuetop20
        inc LEFTDIGITOFFSET
        inc RIGHTDIGITOFFSET
        ldy #0
continuetop20:
        dex
        bne top20

clearPF:
        ; clearing playfield from score display section
        lda #0
        sta PF2
        sta PF1
        sta PF0


        ; sets the appropriate playfield color according to the gametype selected
        ; and also waits 4 scanlines + one extra scanline outside of the main loop
        ldx #4
top4plus1:
        sta WSYNC

        ; set playfield color
        ldy SELECTEDGAMETYPE
        lda snakecolors,y
        sta COLUPF

        dex
        bne top4plus1

        ; set background color
        lda #0
        sta COLUBK
        sta WSYNC ; just once

        ; iterates over 160 scanlines, displaying the entire playfield
        ; also wastes two scanlines at the end
middle160plus3:

loop10: ; loops 10 times, representing each of the 10 rows of the playfield
        ldx #16 ; loop 16 times per "playfield row", making square-ish "pixels"
        ldy LOOPROW
middlerow:
        sta WSYNC ; performed 160 times total

        ; draw snake playfield
        ; columns 1-4
        lda ROWS,y
        and #%11110000
        tay
        lda leftPF2,y
        sta PF2

        ldy LOOPROW

        ; columns 5-6
        lda ROWS,y
        and #%00001100
        tay
        lda rightPF0,y
        sta PF0

        ldy LOOPROW

        ; columns 7-8
        lda ROWS,y
        and #%00000011
        tay
        lda rightPF1,y
        sta PF1

        ; reseting PF2
        lda #0
        sta PF2
        sta PF0
        sta PF1

        ldy LOOPROW
        dex
        bne middlerow

        ; loop back to the top after the 16 pixels of a row have been displayed
        inc LOOPROW
        cpy #$09
        bne loop10
        ; draw snake playfield ended

finalizedraw:
        sta WSYNC ; wasting 1
        
        ; clearing the playfield
        lda #0
        sta PF0
        sta PF1
        sta PF2

        lda #0
        sta COLUBK

        ; wasting 2
        sta WSYNC
        sta WSYNC

        ; setting background color for bottom56
        lda #$0a
        sta COLUBK


        ; iterates 4 times, displaying a bottom bar for the playfield
        ldx #4
bottom4:
        sta WSYNC
        dex
        bne bottom4

        rts
        ; drawing 192 scanlines completed

OverScan:
        sta WSYNC
        lda #2
        sta VBLANK
        lda #32 ; set timer for 27 scanlines, 32 = ((27 * 76) / 64)
        sta TIM64T ; set timer to go off in 27 scanlines
        
        ; game logic can go here
        jsr ProcessSwitches
        jsr PlaceAppleInPlayfield
        jsr PrepScore
        jsr PrepSelectedGame
        jsr ProcessSound
        jsr GenerateRandom
    
OSwait:
        sta WSYNC ; Wait for SYNC (halts CPU until end of scanline)
        lda INTIM ; Check the timer
        bne OSwait ; loop back if the timer has not elapsed all of the waiting time
        rts


;---------------------------------------------------
;
;                 Sound Subroutines                
;
;---------------------------------------------------


EatAppleSound:
        lda #1
        sta AUDC0 ; channel
        lda #8
        sta AUDF0 ; frequency
        lda #3
        sta AUDV0 ; volume
        lda #5
        sta SOUNDITERATOR
        rts

SelectGameSound:
        lda #1
        sta AUDC0 ; channel
        lda #15
        sta AUDF0 ; frequency
        lda #3
        sta AUDV0 ; volume
        lda #5
        sta SOUNDITERATOR
        rts

ProcessSound:
        lda SOUNDITERATOR
        beq turnsoundoff
        dec SOUNDITERATOR
        rts
turnsoundoff:
        lda #0
        sta AUDV0
        rts


;---------------------------------------------------
;
;            General Purpose Subroutines              
;
;---------------------------------------------------


        ; called when the user presses the reset switch on the console
UserReset:

        ; init rows of the 10 x 8 playfield
        ldx #10; 10 rows
initrowsreset:
        dex
        lda #%11111111 ; bits 0-7 all enabled
        sta ROWS,x
        cpx #0
        bne initrowsreset

        ; setting up starting position of snake
        ; NOTE: 0 = snake in this square
        ; using row 6 of the playfield
        lda #%11100111
        sta ROWS + 5

        ; init snake length
        lda #2
        sta SNAKELENGTH

        ; set game speed
        ldx SELECTEDGAMETYPE
        lda snakespeed,x
        sta RENDERSPEED

        ; init score
        lda #0
        sta SCORE

        ; init snake head location
        lda #$2c
        sta SNAKEHEADLOCATION

        ; init snake tail location
        lda #$a8
        sta SNAKEOLDTAILPOINTER

        ; init apple location
        lda #$ff
        sta APPLELOCATION

        ; generate new random number
        jsr GenerateRandom

        ; init snake head direction
        lda #%01111111 ; right
        sta HEADDIRECTION

        ; init head history
        lda #$2a
        sta HEADHISTORY
        lda #$2b
        sta HEADHISTORY + 1
        lda #$2c
        sta HEADHISTORY + 2

        ; init head history pointer
        lda #$aa ; a8 being the start of the history + 2 (assuming the snake is 2 long at the start)
        sta HEADHISTORYPOINTER

        ; setting render counter
        lda #0
        sta RENDERCOUNTER

        ; setting score color
        lda #$0a
        sta COLUPF

        ; setting display table offsets to 0
        lda #0
        sta LEFTDIGITOFFSET
        sta RIGHTDIGITOFFSET
        sta LEVELOFFSET
        sta SELECTEDGAMETYPEOFFSET
        
        rts



ProcessSwitches:
        lda SWCHB ; load in the state of the switches
        lsr ; D0 is now in C
        bcs notreset ; if D0 was on, the RESET switch was not held
        jsr UserReset ; prep for new game 
        lda #0
        sta GAMEMODE      
        rts
        
notreset:
        lsr ; carry flag
        bcs NotSelect

        ; selection mode engaged
        ; set game mode to SELECT mode (#2)
        lda #2
        sta GAMEMODE

        ; checking if user is allowed to make a selection
        ; this is done so the selection won't fall through and
        ; refresh selection at 60Hz
        lda #0
        cmp DEBOUNCE
        bne selected

        ; reset game type selection if the next game type is out of bounds
        lda #2
        cmp SELECTEDGAMETYPE
        beq resetselectedgametype

        ; setting debounce to prevent fall through
        lda #1
        sta DEBOUNCE

        jsr SelectGameSound
        inc SELECTEDGAMETYPE
        jmp selected
resetselectedgametype:
        ; resetting selected gametype to 0
        lda #0
        sta SELECTEDGAMETYPE
        jsr SelectGameSound

        ; setting debounce to prevent fall through
        lda #1
        sta DEBOUNCE
        jmp selected
NotSelect:
        ; if the user has let go of the select lever
        ; they are allowed to select again
        lda #0
        sta DEBOUNCE
selected:
        rts



        ; generate random number
GenerateRandom:
        lda RANDOM
        lsr
        bcc noeor
        eor #$8e
noeor:
        sta RANDOM
        rts



SetDirection:
        ldx SWCHA
        cpx #%11111111 ; no direction selected
        beq nodirection

        cpx #%11101111
        beq normaldirection
        cpx #%11011111
        beq normaldirection
        cpx #%10111111
        beq normaldirection
        cpx #%01111111
        beq normaldirection
        
        jmp nodirection
normaldirection:
        ; check if direction is not opposite to current direction
        lda STOREDDIRECTION
        cmp #%11101111 ; up
        beq isdown
        cmp #%01111111 ; right
        beq isleft
        cmp #%11011111 ; down
        beq isup
        cmp #%10111111 ; left
        beq isright
        jmp nodirection
isdown:
        cpx #%11011111 ; down
        beq nodirection
        jmp storedirection

isleft:
        cpx #%10111111 ; left
        beq nodirection
        jmp storedirection

isright:
        cpx #%01111111 ; right
        beq nodirection
        jmp storedirection

isup:
        cpx #%11101111 ; up
        beq nodirection
        jmp storedirection

storedirection:
        stx HEADDIRECTION
nodirection:
        rts



CheckCollision:
        ldx HEADDIRECTION
        cpx #%11101111 ; up
        bne checkcollisioncontinue1
        jmp up
checkcollisioncontinue1:
        cpx #%01111111 ; right
        bne checkcollisioncontinue2
        jmp right
checkcollisioncontinue2:
        cpx #%11011111 ; down
        bne checkcollisioncontinue3
        jmp down
checkcollisioncontinue3:
        ; left is the only option left
        jmp left



up:
        lda SNAKEHEADLOCATION
        sec
        sbc #$08
        clc
        bpl applecollisionup
        jmp BadCollision ; if value of subtraction is negative
        
applecollisionup:
        ; is collision with an apple?
        lda SNAKEHEADLOCATION
        sec
        sbc APPLELOCATION
        sec
        sbc #$08
        bne collisionresumeup
        clc
        ; increment score
        sed
        lda SCORE
        clc
        adc $01
        sta SCORE
        cld
        ; increment snake length
        inc SNAKELENGTH
        ; setting value of apple location to $ff to know that we need to put apple in new location
        clc ; clears carry
        lda #$ff
        sta APPLELOCATION
        jsr GetRowAndColumnForHead
        jsr MoveHeadHistoryPointerForward
        jsr MoveSnakeUp
        jsr EatAppleSound
        rts
collisionresumeup:
        clc ; clears carry
        ; get row and column of the snake head
        ; check if the square above (up) the snake head is its body (bit = 0)
        jsr GetRowAndColumnForHead

        ldx ROWNUMBER
        dex
        lda ROWS,x
        and COLUMNMASK
        cmp #0
        bne rowsupreturn
        jmp BadCollision

rowsupreturn:
        jsr MoveHeadHistoryPointerForward
        jsr IncrementOldSnakeTailPointer
        jsr MoveSnakeUp
        jsr GetRowAndColumnForTail
        jsr removeoldsnaketail
        rts



right:
        lda #$07
checkright:
        cmp SNAKEHEADLOCATION
        bne checkrightcontinue
        jmp BadCollision
checkrightcontinue:
        clc
        adc #$08
        cmp #$57
        bne checkright
        ; is collision with an apple?
        lda SNAKEHEADLOCATION
        clc
        adc #$01
        cmp APPLELOCATION
        bne collisionresumeright
        ; increment score
        sed
        lda SCORE
        clc
        adc $01
        sta SCORE
        cld
        ; increment snake length
        inc SNAKELENGTH
        ; setting value of apple location to $ff to know that we need to put apple in new location
        lda #$ff
        sta APPLELOCATION
        jsr GetRowAndColumnForHead
        jsr MoveHeadHistoryPointerForward
        jsr MoveSnakeRight
        jsr EatAppleSound
        rts
collisionresumeright:
        ; get row and column of the snake head
        ; check if the square right of the snake head is its body (bit = 0)
        jsr GetRowAndColumnForHead

        ldx ROWNUMBER
        lda ROWS,x
        asl
        and COLUMNMASK
        cmp #0
        bne rowsrightreturn
        jmp BadCollision

rowsrightreturn:
        jsr MoveHeadHistoryPointerForward
        jsr IncrementOldSnakeTailPointer
        jsr MoveSnakeRight
        jsr GetRowAndColumnForTail
        jsr removeoldsnaketail
        rts



down:
        lda SNAKEHEADLOCATION
        clc
        adc #$08
        cmp #$50
        bcc applecollisiondown
        jmp BadCollision ; if $50 is greater than the a register

applecollisiondown:
        ; is collision with an apple?
        lda APPLELOCATION
        sec
        sbc SNAKEHEADLOCATION
        sec
        sbc #$08
        bne collisionresumedown
        clc
        ; increment score
        sed
        lda SCORE
        clc
        adc $01
        sta SCORE
        cld
        ; increment snake length
        inc SNAKELENGTH
        ; setting value of apple location to $ff to know that we need to put apple in new location
        clc ; clear carry
        lda #$ff
        sta APPLELOCATION
        jsr GetRowAndColumnForHead
        jsr MoveHeadHistoryPointerForward
        jsr MoveSnakeDown
        jsr EatAppleSound
        rts
collisionresumedown:
        clc ; clear carry
        ; get row and column of the snake head
        ; check if the square below (down) the snake head is its body (bit = 0)
        jsr GetRowAndColumnForHead

        ldx ROWNUMBER
        inx
        lda ROWS,x
        and COLUMNMASK
        cmp #0
        bne rowsdownreturn
        jmp BadCollision

rowsdownreturn:
        jsr MoveHeadHistoryPointerForward
        jsr IncrementOldSnakeTailPointer
        jsr MoveSnakeDown
        jsr GetRowAndColumnForTail
        jsr removeoldsnaketail
        rts



left:
        lda #$00
checkleft:
        cmp SNAKEHEADLOCATION
        bne checkleftcontinue
        jmp BadCollision
checkleftcontinue:
        clc
        adc #$08
        cmp #$50
        bne checkleft
        ; is collision with an apple?
        lda SNAKEHEADLOCATION
        sec
        sbc #$01
        clc
        cmp APPLELOCATION
        bne collisionresumeleft
        ; increment score
        sed
        lda SCORE
        clc
        adc $01
        sta SCORE
        cld
        ; increment snake length
        inc SNAKELENGTH
        ; setting value of apple location to $ff to know that we need to put apple in new location
        lda #$ff
        sta APPLELOCATION
        jsr GetRowAndColumnForHead
        jsr MoveHeadHistoryPointerForward
        jsr MoveSnakeLeft
        jsr EatAppleSound
        rts
collisionresumeleft:
        ; get row and column of the snake head
        ; check if the square right of the snake head is its body (bit = 0)
        jsr GetRowAndColumnForHead

        ldx ROWNUMBER
        lda ROWS,x
        lsr
        and COLUMNMASK
        cmp #0
        bne rowsleftreturn
        jmp BadCollision

rowsleftreturn:
        jsr MoveHeadHistoryPointerForward
        jsr IncrementOldSnakeTailPointer
        jsr MoveSnakeLeft
        jsr GetRowAndColumnForTail
        jsr removeoldsnaketail
        rts



BadCollision:
        ; set gamemode to #1, meaning game over
        lda #$01
        sta GAMEMODE
        clc
        rts



GetRowAndColumnForHead:
        ldx #0
        lda SNAKEHEADLOCATION
        sec
rowloop:
        sbc #$08
        bmi columnloop
        inx
        jmp rowloop
columnloop:
storerow:
        stx ROWNUMBER
        sec
        lda endofrownumber,x ; rownumber already in x register
        sbc SNAKEHEADLOCATION
        clc
        tax
        lda columnmasklist,x
        sta COLUMNMASK
        lda removetailmasklist,x
        sta COLUMNMASKINVERTED
        
rowvarusedstored:
        clc
        rts



MoveHeadHistoryPointerForward:
        ; update snake on playfield
        lda HEADHISTORYPOINTER
        cmp #$f7
        beq moveforwardheadreset
        ; increment head
        lda HEADHISTORYPOINTER
        clc
        adc #$01
        sta HEADHISTORYPOINTER
        rts
moveforwardheadreset:
        ; reset head history pointer
        lda #$a8
        sta HEADHISTORYPOINTER
        rts



MoveSnakeDown:
        ; load history pointer
        ldx HEADHISTORYPOINTER
        ; snake head location is pushed up
        lda SNAKEHEADLOCATION
        clc
        adc #$08
        sta SNAKEHEADLOCATION
        ; storing snake head location in the head history pointer
        sta #0,x
        ; alter the playfield to reflect the new snake head location
        ldx ROWNUMBER
        inx
        lda ROWS,x ; loading row that needs to be altered
        and COLUMNMASKINVERTED ; turning off bit in row to reflect new position
        sta ROWS,x ; storing row

        ; store direction
        lda HEADDIRECTION
        sta STOREDDIRECTION
        rts



MoveSnakeUp:
        ; load history pointer
        ldx HEADHISTORYPOINTER
        ; snake head location is pushed up
        lda SNAKEHEADLOCATION
        sec
        sbc #$08
        clc
        sta SNAKEHEADLOCATION
        ; storing snake head location in the head history pointer
        sta #0,x
        ; alter the playfield to reflect the new snake head location
        ldx ROWNUMBER
        dex
        lda ROWS,x ; loading row that needs to be altered
        and COLUMNMASKINVERTED ; turning off bit in row to reflect new position
        sta ROWS,x ; storing row

        ; store direction
        lda HEADDIRECTION
        sta STOREDDIRECTION
        rts



MoveSnakeRight:
        ; load history pointer
        ldx HEADHISTORYPOINTER
        ; snake head location is pushed right
        lda SNAKEHEADLOCATION
        clc
        adc #$01
        sta SNAKEHEADLOCATION
        ; storing snake head location in the head history pointer
        sta #0,x
        ; alter the playfield to reflect the new snake head location
        lda COLUMNMASKINVERTED
        lsr
        ora #%10000000
        sta COLUMNMASKINVERTED
        ldx ROWNUMBER
        lda ROWS,x ; loading row that needs to be altered
        and COLUMNMASKINVERTED ; turning off bit in row to reflect new position
        sta ROWS,x ; storing row

        ; store direction
        lda HEADDIRECTION
        sta STOREDDIRECTION
        rts



MoveSnakeLeft:
        ; load history pointer
        ldx HEADHISTORYPOINTER
        ; snake head location is pushed left
        lda SNAKEHEADLOCATION
        sec
        sbc #$01
        clc
        sta SNAKEHEADLOCATION
        ; storing snake head location in the head history pointer
        sta #0,x
        ; alter the playfield to reflect the new snake head location
        lda COLUMNMASKINVERTED
        asl
        ora #%00000001
        sta COLUMNMASKINVERTED
        ldx ROWNUMBER
        lda ROWS,x ; loading row that needs to be altered
        and COLUMNMASKINVERTED ; turning off bit in row to reflect new position
        sta ROWS,x ; storing row

        ; store direction
        lda HEADDIRECTION
        sta STOREDDIRECTION
        rts



IncrementOldSnakeTailPointer:
        lda #$f7
        cmp SNAKEOLDTAILPOINTER
        beq resetoldsnaketailpointer
        inc SNAKEOLDTAILPOINTER
        rts
resetoldsnaketailpointer:
        lda #$a8
        sta SNAKEOLDTAILPOINTER
        rts

removeoldsnaketail:
        ldx ROWNUMBER
        lda ROWS,x
        ora COLUMNMASKINVERTED
        sta ROWS,x
        rts



GetRowAndColumnForTail:
        ldx SNAKEOLDTAILPOINTER
        lda #0,x ; loading tail playfield value
        ldx #0
rowlooptail:
        sec
        sbc #$08
        bmi columnlooptail
        inx
        jmp rowlooptail
columnlooptail:
        clc
storerowtail:
        stx ROWNUMBER
        lda endofrownumber,x
        ldx SNAKEOLDTAILPOINTER
        sec
        sbc #0,x ; loading tail playfield value
        clc
        tax
        lda removetailmasklist,x
        sta COLUMNMASK
        lda columnmasklist,x
        sta COLUMNMASKINVERTED
rowvarusedstoredtail:
        clc
        rts



PlaceAppleInPlayfield:
        lda #$ff
        cmp APPLELOCATION
        beq processapple
        jmp noprocessingneeded
processapple:
        ; use one of two random algorithms
        ; this accounts for random number generation's pseudo-random value
        ; thus improving apparent randomness
        lda RANDOM
        and #1
        cmp #1
        beq randomalgo2
randomalgo1:
        ; random number 1st variation
        ; get space available
        sec
        lda #SIZEOFMAP
        sbc SNAKELENGTH
        clc
        ; restrict random number to space available
        and RANDOM
        lsr
        tay
        jmp randomcontinue
randomalgo2:
        ; random number 2st variation
        ; get space available
        sec
        lda #SIZEOFMAP
        sbc SNAKELENGTH
        clc
        ; restrict random number to space available
        and RANDOM
        tay
randomcontinue:
        ; set y to 1 if y = 0, this prevents a register overflow
        cpy #0
        bne initrowloopapple
        ldy #1
        ; loop through 10 columns of rows
        ; this is not very DRY code due to the need to keep this within cycle count restrictions
initrowloopapple:
        ldx #0
rowloopapple:
        lda ROWS,x
        cmp #0
        bne rowcol8
        jmp rowloopcontinue
rowcol8:
        ror
        bcc rowcol7
        dey
        cpy #0
        bne rowcol7
        lda ROWS,x
        and #%11111110
        sta ROWS,x

        lda #$07
        jmp storeapplelocationloop
rowcol7:
        ror
        bcc rowcol6
        dey
        cpy #0
        bne rowcol6
        lda ROWS,x
        and #%11111101
        sta ROWS,x

        lda #$06
        jmp storeapplelocationloop
rowcol6:
        ror
        bcc rowcol5
        dey
        cpy #0
        bne rowcol5
        lda ROWS,x
        and #%11111011
        sta ROWS,x

        lda #$05
        jmp storeapplelocationloop
rowcol5:
        ror
        bcc rowcol4
        dey
        cpy #0
        bne rowcol4
        lda ROWS,x
        and #%11110111
        sta ROWS,x

        lda #$04
        jmp storeapplelocationloop
rowcol4:
        ror
        bcc rowcol3
        dey
        cpy #0
        bne rowcol3
        lda ROWS,x
        and #%11101111
        sta ROWS,x

        lda #$03
        jmp storeapplelocationloop
rowcol3:
        ror
        bcc rowcol2
        dey
        cpy #0
        bne rowcol2
        lda ROWS,x
        and #%11011111
        sta ROWS,x

        lda #$02
        jmp storeapplelocationloop
rowcol2:
        ror
        bcc rowcol1
        dey
        cpy #0
        bne rowcol1
        lda ROWS,x
        and #%10111111
        sta ROWS,x

        lda #$01
        jmp storeapplelocationloop
rowcol1:
        ror
        bcc rowloopcontinue
        dey
        cpy #0
        bne rowloopcontinue
        lda ROWS,x
        and #%01111111
        sta ROWS,x

        lda #$00
        jmp storeapplelocationloop

rowloopcontinue:
        cpx #9
        beq storeapplelocationloop
        inx
        jmp rowloopapple

storeapplelocationloop:
        dex
        cpx #$ff
        beq finishappleplacement
        clc
        adc #$08
        jmp storeapplelocationloop

finishappleplacement:
        sta APPLELOCATION

noprocessingneeded:
        rts



PrepSelectedGame:
        lda SELECTEDGAMETYPE
        cmp #0
        beq prepselected0
        cmp #1
        beq prepselected1
        cmp #2
        beq prepselected2
        jmp returnprepselectedgame

prepselected0:
        lda #5
        sta SELECTEDGAMETYPEOFFSET
        jmp returnprepselectedgame
prepselected1:
        lda #0
        sta SELECTEDGAMETYPEOFFSET
        jmp returnprepselectedgame
prepselected2:
        lda #10
        sta SELECTEDGAMETYPEOFFSET

returnprepselectedgame:
        rts



PrepScore:
        ; left digit
        lda SCORE
        and #%11110000
        lsr
        lsr
        lsr
        lsr

        ; get offset of left digit
        tax
        lda #0
leftdigitloop:
        cpx #0
        beq storeleftdigitoffset
        clc
        adc #5
        dex
        jmp leftdigitloop
storeleftdigitoffset:
        sta LEFTDIGITOFFSET

        ; right digit
        lda SCORE
        and #%00001111

        ; get offset of right digit
        tax
        lda #0
rightdigitloop:
        cpx #0
        beq storerightdigitoffset
        clc
        adc #5
        dex
        jmp rightdigitloop
storerightdigitoffset:
        sta RIGHTDIGITOFFSET
        
        rts


;---------------------------------------------------
;
;                    Data Tables                     
;
;---------------------------------------------------


digits:
        ; left and right digits are represented in each byte (4 bits per digit)
        ; zero
        .byte %11100000
        .byte %10100000
        .byte %10100000
        .byte %10100000
        .byte %11100000

        ; one
        .byte %10000000
        .byte %10000000
        .byte %10000000
        .byte %10000000
        .byte %10000000
        
        ; two
        .byte %11100000
        .byte %10000000
        .byte %11100000
        .byte %00100000
        .byte %11100000

        ; three
        .byte %11100000
        .byte %10000000
        .byte %11000000
        .byte %10000000
        .byte %11100000

        ; four
        .byte %10100000
        .byte %10100000
        .byte %11100000
        .byte %10000000
        .byte %10000000

        ; five
        .byte %11100000
        .byte %00100000
        .byte %11100000
        .byte %10000000
        .byte %11100000

        ; six
        .byte %11100000
        .byte %00100000
        .byte %11100000
        .byte %10100000
        .byte %11100000

        ; seven
        .byte %11100000
        .byte %10000000
        .byte %10000000
        .byte %10000000
        .byte %10000000

        ; eight
        .byte %11100000
        .byte %10100000
        .byte %11100000
        .byte %10100000
        .byte %11100000

        ; nine
        .byte %11100000
        .byte %10100000
        .byte %11100000
        .byte %10000000
        .byte %11100000

levelletter:
        .byte #%00010000
        .byte #%00010000
        .byte #%00010000
        .byte #%00010000
        .byte #%11110000

leftPF2:
        ; Left PF2 (mirrored)
        .byte %00000000
        ds 15
        .byte %11000000 ; %00010000
        ds 15
        .byte %00110000 ; %00100000
        ds 15
        .byte %11110000 ; %00110000
        ds 15
        .byte %00001100 ; %01000000
        ds 15
        .byte %11001100 ; %01010000
        ds 15
        .byte %00111100 ; %01100000
        ds 15
        .byte %11111100 ; %01110000
        ds 15
        .byte %00000011 ; %10000000
        ds 15
        .byte %11000011 ; %10010000
        ds 15
        .byte %00110011 ; %10100000
        ds 15
        .byte %11110011 ; %10110000
        ds 15
        .byte %00001111 ; %11000000
        ds 15
        .byte %11001111 ; %11010000
        ds 15
        .byte %00111111 ; %11100000
        ds 15
        .byte %11111111 ; %11110000

rightPF0:
        ; Right PF0
        .byte %00000000
        ds 3
        .byte %11000000
        ds 3
        .byte %00110000
        ds 3
        .byte %11110000

rightPF1:
        ; Right PF1
        .byte %00000000
        .byte %00110000
        .byte %11000000
        .byte %11110000

endofrownumber:
        .byte #$07
        .byte #$0f
        .byte #$17
        .byte #$1f
        .byte #$27
        .byte #$2f
        .byte #$37
        .byte #$3f
        .byte #$47
        .byte #$4f

columnmasklist:
        .byte #%00000001
        .byte #%00000010
        .byte #%00000100
        .byte #%00001000
        .byte #%00010000
        .byte #%00100000
        .byte #%01000000
        .byte #%10000000

removetailmasklist:
        .byte #%11111110
        .byte #%11111101
        .byte #%11111011
        .byte #%11110111
        .byte #%11101111
        .byte #%11011111
        .byte #%10111111
        .byte #%01111111

snakecolors:
        .byte #SNAKECOLORNORMAL
        .byte #SNAKECOLORSLOW
        .byte #SNAKECOLORFAST

snakespeed:
        .byte #SPEEDNORMAL
        .byte #SPEEDSLOW
        .byte #SPEEDFAST


;---------------------------------------------------
;
;             Setting Interrupt Vectors               
;
;---------------------------------------------------


        ORG $FFFA ; set address to 6507 Interrupt Vectors 
        .WORD InitSystem ; NMI
        .WORD InitSystem ; RESET
        .WORD InitSystem ; IRQ        
