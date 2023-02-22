//LAB FOUR PART THREE
               .equ      EDGE_TRIGGERED,    0x1
               .equ      LEVEL_SENSITIVE,   0x0
               .equ      CPU0,              0x01    // bit-mask; bit 0 represents cpu0
               .equ      ENABLE,            0x1

               .equ      KEY0,              0b0001
               .equ      KEY1,              0b0010
               .equ      KEY2,              0b0100
               .equ      KEY3,              0b1000

               .equ      IRQ_MODE,          0b10010
               .equ      SVC_MODE,          0b10011

               .equ      INT_ENABLE,        0b01000000
               .equ      INT_DISABLE,       0b11000000

/*********************************************************************************
 * Initialize the exception vector table
 ********************************************************************************/
                .section .vectors, "ax"

                B        _start             // reset vector
                .word    0                  // undefined instruction vector
                .word    0                  // software interrrupt vector
                .word    0                  // aborted prefetch vector
                .word    0                  // aborted data vector
                .word    0                  // unused vector
                B        IRQ_HANDLER        // IRQ interrupt vector
                .word    0                  // FIQ interrupt vector

/* ********************************************************************************
 * This program demonstrates use of interrupts with assembly code. The program 
 * responds to interrupts from a timer and the pushbutton KEYs in the FPGA.
 *
 * The interrupt service routine for the timer increments a counter that is shown
 * on the red lights LEDR by the main program. The counter can be stopped/run by 
 * pressing any of the KEYs.
 ********************************************************************************/
                .text
                .global  _start
				
_start:         //For safety, intialize R3 to 0 
                //
				/* Set up stack pointers for IRQ and SVC processor modes */
                MOV      R1, #0b11010010    //I bit= 1: interrupts disabled, Mode=10010: IRQ
                MSR      CPSR_c, R1        //Modify the lower 8 bits of the CPSR to change into IRQ                   
                LDR      SP, =0x40000     //Initalize R13_IRQ sp to point far away from our program 
				
				MOV      R1, #0b11010011   //I bit =1: interrupts disabled, Mode=10011: SVC
                MSR      CPSR_c, R1       //Modify the lower 8 bits of the CPSR to change into SVC
                LDR      SP, =0x20000    //Initalize R13_SVC sp to point far away from our program 

                BL       CONFIG_GIC           // configure the ARM generic interrupt controller                        

                BL       CONFIG_PRIV_TIMER   // configure A9 Private Timer
                BL       CONFIG_KEYS        // configure the pushbutton KEYS port
                                              				  
               // enable IRQ interrupts in the processor
               MOV      R0, #0b01010011  //I bit =0: Interrupts enabled, Mode=10011: SVC
               MSR      CPSR_c, R0      //Modify lower 8 bits of the CPSR to change into SVC 
				                       //w/enabled interrupts	  
				
			   //Load into R5 the LEDR base address
               LDR      R5, =0xFF200000    
			
LOOP:          LDR      R3, COUNT    // global variable
               STR      R3, [R5]    // write to the LEDR lights
               B        LOOP                
          

/* Global variables */
//Count is initalized to 0 and run is initalized to 1
                .global  COUNT
COUNT:          .word    0x5       // used by timer
                .global  RUN
RUN:            .word    0x1      // initial value to increment COUNT

/* Configure the A9 Private Timer to create interrupts at 0.25 second intervals */
CONFIG_PRIV_TIMER:  LDR R0, =0x2FAF080  //Load 50 million into R0 
                    LDR R1, =0xFFFEC600 //Load the address of the timer's Load Register into R1 
					STR R0, [R1] //Store 50 Million into the timer's load register 
					MOV R0, #7  //R0<- 111
					STR R0, [R1, #0x8] //Store a 1 into I, A, and E bit of control register
					                  //to start the timer, enable auto mode, and enable interrupts
									 //each time the counter reaches 0 
                    MOV      PC, LR
                   
/* Configure the pushbutton KEYS to generate interrupts */
CONFIG_KEYS:    LDR      R0, =0xFF200050      //Load pushbutton KEY base address into R0
                MOV      R1, #0xF            // R1<- 1111
                STR      R1, [R0, #0x8]     // Enable interrupts by storing ones into IMR 
                MOV      PC, LR

/*--- IRQ ---------------------------------------------------------------------*/
IRQ_HANDLER:  PUSH  {R0-R7, LR}
              LDR   R4, =0xFFFEC100  //An address that can be incremented to access ICCIAR or ICCEOIR
			  LDR   R5, [R4, #0x0C] //Load into R5, the ICCIAR, which will contain the interrupt ID
			  
CHECK_KEYS: CMP R5, #73 
            BNE CHECK_TIMER
			BL KEY_ISR
			B EXIT_IRQ 
			
CHECK_TIMER: CMP R5, #29 
             BNE UNEXPECTED
			 BL PRIV_TIMER_ISR
			 B EXIT_IRQ

UNEXPECTED: B UNEXPECTED
			                     
                
EXIT_IRQ:	STR R5, [R4, #0x10] //Store interrupt ID into ICCEOIR to tell the processor to 
                                //turn off that interrupt 
            POP     {R0-R7, LR} 	
            SUBS    PC, LR, #4

/****************************************************************************************
 * Pushbutton - Interrupt Service Routine                                
 *                                                                          
 * This routine toggles the RUN global variable.
 //Address of the LEDs is stored in R5 
 ***************************************************************************************/
                .global  KEY_ISR
				
KEY_ISR:        PUSH {R4-R10, LR}
                LDR R5, =0xFF20005C 
				LDR R6, [R5]  //Read the edge capture register into R6 
				
CHECK_ZERO:    CMP R6, #1
			   BNE CHECK_ONE
			   B ZERO_EXECUTE

CHECK_ONE:     CMP R6, #2
			   BNE CHECK_TWO
			   B ONE_EXECUTE

CHECK_TWO:     CMP R6, #4
			   BNE DONE
			   B TWO_EXECUTE

ZERO_EXECUTE:   LDR R4, RUN        //LOAD RUN into R4
				CMP R4, #0        //Compute R4-0
				MOVGT R4, #0     //If R4-0 >0, it means RUN was a 1, so make it a zero 
				MOVEQ R4, #1    //if R4-0 =0, it means RUN was a 0, so make it a one 
				STR R4, RUN    //Change the value of RUN 
				B DONE

ONE_EXECUTE:    //Stop the timer 
               LDR R7, =0xFFFEC600  //Load the address of the timer's load register into R7
			   
			   MOV R10, #0 
			   STR R10, [R7, #8] //Stop the timer 
			   
               LDR R8, [R7]   //Read from memory the current value in the timer's load register into R8 
			   LSR R8, R8, #1 //Shift the number right by one bit to divide by 2^1
			                  //Loading the counter with half its value will double the speed
							  
			   STR R8, [R7] //reload the timer with the new value 
			   MOV R9, #7  //R0<- 111
			   STR R9, [R7, #0x8]  //restart the timer 
			   B DONE

TWO_EXECUTE:   
               LDR R7, =0xFFFEC600 
			   
			   MOV R10, #0 
			   STR R10, [R7, #8] //Stop the timer 
			   
               LDR R8, [R7] 
			   LSL R8, R8, #1 //Shift the number left by one bit to multiply by 2^1 
			                 //Loading the counter with double its value will halve its speed
							 
			   STR R8, [R7] //reload the timer with the new value 
			   MOV R9, #7  //R9<- 111
			   STR R9, [R7, #0x8]  //restart the timer   
			   B DONE 
			   
			   
			   
DONE: 			STR R6, [R5]  //Reset the ECR to acknowledge that key press was received
				              //If you don't reset the edge capture, it will continue sending interrupts.
                POP {R4-R10, LR}
                MOV  PC, LR

/******************************************************************************
 * A9 Private Timer interrupt service routine
 *                                                                          
 * This code toggles performs the operation COUNT = COUNT + RUN
 *****************************************************************************/
                .global    TIMER_ISR
PRIV_TIMER_ISR: PUSH {R4-R7, LR}
                LDR R4, COUNT     //Store COUNT into R4
				LDR R5, RUN      //Store RUN into R5
				ADD R4, R5      //R4 <- COUNT + RUN 
				STR R4, COUNT  //COUNT <- COUNT + RUN 
				LDR R6, =0xFFFEC60C //Get memory address of F bit 
				LDR R7, [R6]         //Read F bit into R7 (Load = read) 
				STR R7, [R6] //Store the F bit into Control register to clear the interrupt
				POP {R4-R7, LR}
                MOV  PC, LR
/* 
 * Configure the Generic Interrupt Controller (GIC)
*/
                .global  CONFIG_GIC
CONFIG_GIC:
                PUSH     {LR}
                MOV      R0, #29
                MOV      R1, #CPU0
                BL       CONFIG_INTERRUPT
                
                /* Enable the KEYs interrupts */
                MOV      R0, #73
                MOV      R1, #CPU0
                /* CONFIG_INTERRUPT (int_ID (R0), CPU_target (R1)); */
                BL       CONFIG_INTERRUPT

                /* configure the GIC CPU interface */
                LDR      R0, =0xFFFEC100        // base address of CPU interface
                /* Set Interrupt Priority Mask Register (ICCPMR) */
                LDR      R1, =0xFFFF            // enable interrupts of all priorities levels
                STR      R1, [R0, #0x04]
                /* Set the enable bit in the CPU Interface Control Register (ICCICR). This bit
                 * allows interrupts to be forwarded to the CPU(s) */
                MOV      R1, #1
                STR      R1, [R0]
    
                /* Set the enable bit in the Distributor Control Register (ICDDCR). This bit
                 * allows the distributor to forward interrupts to the CPU interface(s) */
                LDR      R0, =0xFFFED000
                STR      R1, [R0]    
    
                POP      {PC}
/* 
 * Configure registers in the GIC for an individual interrupt ID
 * We configure only the Interrupt Set Enable Registers (ICDISERn) and Interrupt 
 * Processor Target Registers (ICDIPTRn). The default (reset) values are used for 
 * other registers in the GIC
 * Arguments: R0 = interrupt ID, N
 *            R1 = CPU target
*/
CONFIG_INTERRUPT: PUSH     {R4-R5, LR}
    
                /* Configure Interrupt Set-Enable Registers (ICDISERn). 
                 * reg_offset = (integer_div(N / 32) * 4
                 * value = 1 << (N mod 32) */
                LSR      R4, R0, #3               // calculate reg_offset
                BIC      R4, R4, #3               // R4 = reg_offset
                LDR      R2, =0xFFFED100
                ADD      R4, R2, R4               // R4 = address of ICDISER
    
                AND      R2, R0, #0x1F            // N mod 32
                MOV      R5, #1                   // enable
                LSL      R2, R5, R2               // R2 = value

                /* now that we have the register address (R4) and value (R2), we need to set the
                 * correct bit in the GIC register */
                LDR      R3, [R4]                 // read current register value
                ORR      R3, R3, R2               // set the enable bit
                STR      R3, [R4]                 // store the new register value

                /* Configure Interrupt Processor Targets Register (ICDIPTRn)
                  * reg_offset = integer_div(N / 4) * 4
                  * index = N mod 4 */
                BIC      R4, R0, #3               // R4 = reg_offset
                LDR      R2, =0xFFFED800
                ADD      R4, R2, R4               // R4 = word address of ICDIPTR
                AND      R2, R0, #0x3             // N mod 4
                ADD      R4, R2, R4               // R4 = byte address in ICDIPTR

                /* now that we have the register address (R4) and value (R2), write to (only)
                 * the appropriate byte */
                STRB     R1, [R4]
    
                POP      {R4-R5, PC}
                .end   
	
